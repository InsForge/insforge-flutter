import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Records each request's decoded JSON body + headers and returns a canned
/// JSON response with a fixed status code.
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.responseBody, {this.statusCode = 200});

  final String responseBody;
  final int statusCode;

  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
  final List<Map<String, List<String>>> headers = <Map<String, List<String>>>[];
  final List<String> paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    headers.add(
      options.headers.map(
        (k, v) => MapEntry(k, <String>[v.toString()]),
      ),
    );

    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = chunks.expand((c) => c).toList();
      final text = utf8.decode(bytes);
      if (text.isNotEmpty) {
        bodies.add(jsonDecode(text) as Map<String, dynamic>);
      }
    }

    return ResponseBody.fromString(
      responseBody,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
