// packages/insforge_database/test/_recording_adapter.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A captured request: the fields tests assert against.
class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, dynamic> queryParameters;
  final Map<String, String> headers;

  /// The decoded JSON request body (List/Map), or null when there was none.
  final Object? body;
}

/// Records every request and returns a fixed response.
///
/// Configure the canned response with [responseBody] (a JSON-encodable
/// value), [statusCode], and [responseHeaders] (e.g. Content-Range).
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter({
    Object? responseBody = const <dynamic>[],
    this.statusCode = 200,
    Map<String, List<String>>? responseHeaders,
  })  : _responseBody = responseBody,
        _responseHeaders = responseHeaders ?? const <String, List<String>>{};

  final Object? _responseBody;
  final int statusCode;
  final Map<String, List<String>> _responseHeaders;

  final List<CapturedRequest> requests = <CapturedRequest>[];

  /// The single captured request (fails if not exactly one was made).
  CapturedRequest get single => requests.single;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? decodedBody;
    final raw = options.data;
    if (raw is String && raw.isNotEmpty) {
      decodedBody = jsonDecode(raw);
    } else if (raw != null) {
      decodedBody = raw;
    }

    requests.add(
      CapturedRequest(
        method: options.method,
        path: options.path,
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
        headers: options.headers.map(
          (String k, dynamic v) => MapEntry<String, String>(k, '$v'),
        ),
        body: decodedBody,
      ),
    );

    final headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      ..._responseHeaders,
    };

    return ResponseBody.fromString(
      _responseBody == null ? '' : jsonEncode(_responseBody),
      statusCode,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}
