// packages/insforge_functions/lib/src/functions_client.dart
import 'package:insforge_core/insforge_core.dart';

/// Client for invoking InsForge edge functions (Deno runtime).
///
/// Functions are executed via the `${baseUrl}/functions/{slug}` path — note
/// there is **no** `/api` prefix, unlike the other modules. The SDK enforces no
/// additional auth; each function enforces its own. The shared
/// [InsforgeHttpClient] still injects the default `Authorization`/`x-api-key`
/// headers, which a function may choose to read.
class FunctionsClient {
  FunctionsClient(this._http);

  final InsforgeHttpClient _http;

  /// Invokes the edge function identified by [slug].
  ///
  /// * [method] — HTTP verb (default `POST`). For body-bearing verbs
  ///   (`POST`/`PUT`/`PATCH`) the [body] is sent as the JSON request body; for
  ///   `GET`/`DELETE` the [body] is ignored and [queryParameters] are sent.
  /// * [body] — JSON-serializable request payload.
  /// * [headers] — extra headers merged onto the request.
  /// * [queryParameters] — URL query parameters.
  ///
  /// Returns the decoded response: a `Map<String, dynamic>` or `List` for JSON
  /// bodies, or a raw `String`/bytes for non-JSON responses. A non-2xx response
  /// throws an [InsforgeHttpException] (e.g. 404 function not found / not
  /// active; 502 Deno runtime failure).
  Future<dynamic> invoke(
    String slug, {
    String method = 'POST',
    Object? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final sendsBody = _methodSendsBody(method);
    final response = await _http.request<dynamic>(
      method,
      '/functions/$slug',
      data: sendsBody ? body : null,
      queryParameters: queryParameters,
      headers: headers,
    );
    return response.data;
  }

  /// Typed convenience over [invoke]: invokes [slug] and maps the JSON object
  /// response through [fromJson].
  ///
  /// Throws an [InsforgeSerializationException] if the response is not a JSON
  /// object.
  Future<T> invokeAs<T>(
    String slug,
    T Function(Map<String, dynamic> json) fromJson, {
    String method = 'POST',
    Object? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final data = await invoke(
      slug,
      method: method,
      body: body,
      headers: headers,
      queryParameters: queryParameters,
    );
    if (data is Map<String, dynamic>) {
      return fromJson(data);
    }
    throw InsforgeSerializationException(
      'Expected a JSON object from function "$slug" but got '
      '${data.runtimeType}.',
    );
  }

  bool _methodSendsBody(String method) {
    final m = method.toUpperCase();
    return m == 'POST' || m == 'PUT' || m == 'PATCH';
  }
}
