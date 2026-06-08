// packages/insforge_functions/test/functions_invoke_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:insforge_functions/insforge_functions.dart';
import 'package:test/test.dart';

/// Records each request and returns a fixed JSON 200.
class RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<String> bodies = <String>[];
  String responseJson;

  RecordingAdapter([this.responseJson = '{"message":"Hello, World!"}']);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = chunks.expand((Uint8List c) => c).toList();
      bodies.add(utf8.decode(bytes));
    } else {
      bodies.add('');
    }
    return ResponseBody.fromString(
      responseJson,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

InsforgeHttpClient _client(RecordingAdapter adapter) {
  final client = InsforgeHttpClient(
    baseUrl: 'https://x.insforge.app',
    anonKey: 'anon-123',
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  group('FunctionsClient.invoke', () {
    test('POSTs to /functions/{slug} with a JSON body and returns decoded data',
        () async {
      final adapter = RecordingAdapter('{"message":"Hello, John!"}');
      final functions = FunctionsClient(_client(adapter));

      final result = await functions.invoke(
        'hello-world',
        body: <String, dynamic>{'name': 'John'},
      );

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/functions/hello-world');
      expect(
        jsonDecode(adapter.bodies.single),
        <String, dynamic>{'name': 'John'},
      );
      expect(result, <String, dynamic>{'message': 'Hello, John!'});
    });

    test('GET override routes correctly and sends query params, not a body',
        () async {
      final adapter = RecordingAdapter();
      final functions = FunctionsClient(_client(adapter));

      await functions.invoke(
        'search',
        method: 'GET',
        queryParameters: <String, dynamic>{'q': 'flutter'},
      );

      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/functions/search');
      expect(req.uri.queryParameters['q'], 'flutter');
      expect(adapter.bodies.single, isEmpty);
    });

    test('forwards custom headers', () async {
      final adapter = RecordingAdapter();
      final functions = FunctionsClient(_client(adapter));

      await functions.invoke(
        'webhook',
        body: <String, dynamic>{'ok': true},
        headers: <String, String>{'X-Custom': 'value-42'},
      );

      expect(adapter.requests.single.headers['X-Custom'], 'value-42');
    });

    test('returns a decoded list when the function responds with a JSON array',
        () async {
      final adapter = RecordingAdapter('[1,2,3]');
      final functions = FunctionsClient(_client(adapter));

      final result = await functions.invoke('numbers');

      expect(result, <int>[1, 2, 3]);
    });
  });
}
