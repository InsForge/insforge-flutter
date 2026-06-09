import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Returns a streamed response whose body yields the supplied SSE [lines]
/// (each already a full `data: {...}` payload) terminated by `data: [DONE]`.
///
/// Lines are emitted across multiple chunks (with a split mid-line) to prove
/// the parser correctly buffers partial SSE frames.
class SseAdapter implements HttpClientAdapter {
  SseAdapter(this.dataPayloads);

  /// Each entry is the JSON string after `data: ` (without the prefix).
  final List<String> dataPayloads;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final buffer = StringBuffer();
    for (final payload in dataPayloads) {
      buffer.write('data: $payload\n\n');
    }
    buffer.write('data: [DONE]\n\n');
    final full = buffer.toString();

    // Split the byte stream at an awkward offset to exercise buffering.
    final bytes = utf8.encode(full);
    final mid = bytes.length ~/ 2;
    final stream = Stream<Uint8List>.fromIterable(<Uint8List>[
      Uint8List.fromList(bytes.sublist(0, mid)),
      Uint8List.fromList(bytes.sublist(mid)),
    ]);

    return ResponseBody(
      stream,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
