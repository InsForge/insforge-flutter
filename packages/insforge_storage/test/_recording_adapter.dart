// packages/insforge_storage/test/_recording_adapter.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A captured request: the fields storage tests assert against.
class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.headers,
    required this.body,
    required this.isFormData,
    required this.formFieldNames,
    required this.formFileFieldNames,
  });

  final String method;
  final String path;
  final Map<String, dynamic> queryParameters;
  final Map<String, String> headers;

  /// The decoded JSON request body (Map/List), or null when there was none or
  /// the body was multipart.
  final Object? body;

  /// True when the request body was a dio [FormData] (multipart upload).
  final bool isFormData;

  /// Ordered names of the FormData's plain fields (`fields`).
  final List<String> formFieldNames;

  /// Ordered names of the FormData's file parts (`files`).
  final List<String> formFileFieldNames;

  /// All FormData part names in submission order (plain fields then files as
  /// dio serializes them); convenient for asserting the `file` part exists.
  bool get hasFileField => formFileFieldNames.contains('file');
}

/// Records every request and returns a fixed response.
///
/// Configure the canned response with [responseBody] (a JSON-encodable value
/// serialized to a string, or a raw string when [rawBody] is true),
/// [statusCode], and [responseHeaders].
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter({
    Object? responseBody = const <String, dynamic>{},
    this.statusCode = 200,
    this.rawBody = false,
    Map<String, List<String>>? responseHeaders,
  })  : _responseBody = responseBody,
        _responseHeaders = responseHeaders ?? const <String, List<String>>{};

  final Object? _responseBody;
  final int statusCode;
  final bool rawBody;
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
    final raw = options.data;
    final isForm = raw is FormData;

    Object? decodedBody;
    final formFieldNames = <String>[];
    final formFileFieldNames = <String>[];

    if (isForm) {
      for (final MapEntry<String, String> f in raw.fields) {
        formFieldNames.add(f.key);
      }
      for (final MapEntry<String, MultipartFile> f in raw.files) {
        formFileFieldNames.add(f.key);
      }
    } else if (raw is String && raw.isNotEmpty) {
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
        isFormData: isForm,
        formFieldNames: formFieldNames,
        formFileFieldNames: formFileFieldNames,
      ),
    );

    final headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      ..._responseHeaders,
    };

    final bodyString = _responseBody == null
        ? ''
        : (rawBody ? _responseBody.toString() : jsonEncode(_responseBody));

    return ResponseBody.fromString(bodyString, statusCode, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}
