// packages/insforge/lib/src/core/http_client.dart
import 'package:dio/dio.dart';

import 'error_response.dart';
import 'errors.dart';
import 'logging_interceptor.dart';
import 'options.dart';
import 'url.dart';
import 'version.dart';

/// Supplies an access token on demand (e.g. from an external auth provider).
typedef AccessTokenProvider = String? Function();

/// Performs a token refresh and returns the new access token. Throws on failure.
typedef RefreshCallback = Future<String> Function();

/// Shared HTTP transport for all InsForge SDK modules.
///
/// Wraps a single [Dio]. Injects `Authorization`/`x-api-key` headers per
/// request, refreshes the access token once on 401 (deduped across concurrent
/// failures — see Task 12), and maps transport errors to [InsforgeException]s.
class InsforgeHttpClient {
  InsforgeHttpClient({
    required String baseUrl,
    required this.anonKey,
    this.apiKey,
    this.options = const InsforgeOptions(),
    this.accessTokenProvider,
    Dio? dio,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        dio = dio ?? Dio() {
    _configure();
  }

  final String baseUrl;
  final String anonKey;
  final String? apiKey;
  final InsforgeOptions options;
  final Dio dio;

  /// Optional external token provider, consulted after the session token.
  AccessTokenProvider? accessTokenProvider;

  /// The current session access token, or null when signed out.
  String? accessToken;

  RefreshCallback? _refreshCallback;

  /// Registers the callback used to refresh the access token on a 401.
  void registerRefreshCallback(RefreshCallback callback) {
    _refreshCallback = callback;
  }

  void _configure() {
    dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = options.connectTimeout
      ..receiveTimeout = options.receiveTimeout
      ..headers = <String, dynamic>{
        'User-Agent': insforgeUserAgent,
        ...options.customHeaders,
      }
      ..validateStatus =
          (int? status) => status != null && status >= 200 && status < 300;

    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
    if (options.logLevel != LogLevel.none) {
      dio.interceptors.add(LoggingInterceptor(options.logLevel));
    }
  }

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.headers.containsKey('Authorization')) {
      final token = accessToken ?? accessTokenProvider?.call() ?? anonKey;
      options.headers['Authorization'] = 'Bearer $token';
    }
    if (apiKey != null && !options.headers.containsKey('x-api-key')) {
      options.headers['x-api-key'] = apiKey;
    }
    handler.next(options);
  }

  Future<String>? _inflightRefresh;

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final canRefresh = response?.statusCode == 401 &&
        _refreshCallback != null &&
        !_isAuthExemptPath(err.requestOptions.path) &&
        err.requestOptions.extra['__insforge_retried__'] != true;

    if (!canRefresh) {
      handler.next(err);
      return;
    }

    try {
      final newToken = await _refreshOnce();
      final req = err.requestOptions;
      req.extra['__insforge_retried__'] = true;
      req.headers['Authorization'] = 'Bearer $newToken';
      final retried = await dio.fetch<dynamic>(req);
      handler.resolve(retried);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<String> _refreshOnce() {
    return _inflightRefresh ??=
        _refreshCallback!().whenComplete(() => _inflightRefresh = null);
  }

  bool _isAuthExemptPath(String path) {
    return path.contains('/api/auth/refresh') ||
        path.endsWith('/api/auth/users') ||
        path.endsWith('/api/auth/sessions');
  }

  /// Performs a request, mapping transport/HTTP errors to [InsforgeException].
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    ResponseType? responseType,
  }) async {
    try {
      return await dio.request<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: headers,
          responseType: responseType,
        ),
      );
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Maps a [DioException] to the appropriate [InsforgeException].
  InsforgeException mapDioError(DioException e) {
    final response = e.response;
    if (response != null) {
      final data = response.data;
      final parsed = data is Map<String, dynamic>
          ? ErrorResponse.fromJson(data)
          : ErrorResponse(message: data?.toString() ?? 'HTTP ${response.statusCode}');
      return InsforgeHttpException(
        statusCode: response.statusCode ?? -1,
        message: parsed.message,
        error: parsed.error,
        nextActions: parsed.nextActions,
        cause: e,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return InsforgeNetworkException(e.message ?? 'Network error', cause: e);
      default:
        return InsforgeException(e.message ?? 'Unknown error', cause: e);
    }
  }
}
