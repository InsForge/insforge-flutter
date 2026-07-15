// packages/insforge_core/lib/src/logging_interceptor.dart
import 'package:dio/dio.dart';

import 'options.dart';

/// Sink for log lines. Defaults to nothing (caller supplies one).
typedef LogSink = void Function(String message);

/// Lightweight dio interceptor that logs requests/responses at the configured
/// [LogLevel], redacting sensitive headers.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor(this.level, {LogSink? sink}) : sink = sink ?? _noop;

  final LogLevel level;
  final LogSink sink;

  static void _noop(String _) {}

  bool get _enabled => level.index >= LogLevel.info.index;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_enabled) {
      sink(
        '→ ${options.method} ${options.uri} headers=${_redact(options.headers)}',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (_enabled) {
      sink('← ${response.statusCode} ${response.requestOptions.uri}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (level.index >= LogLevel.error.index && level != LogLevel.none) {
      sink(
        '✗ ${err.response?.statusCode ?? '-'} ${err.requestOptions.uri}: ${err.message}',
      );
    }
    handler.next(err);
  }

  Map<String, dynamic> _redact(Map<String, dynamic> headers) {
    final copy = Map<String, dynamic>.of(headers);
    if (copy.containsKey('Authorization')) copy['Authorization'] = 'Bearer ***';
    if (copy.containsKey('x-api-key')) copy['x-api-key'] = '***';
    return copy;
  }
}
