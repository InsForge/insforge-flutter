// packages/insforge_functions/test/functions_error_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:insforge_functions/insforge_functions.dart';
import 'package:test/test.dart';

/// Tiny typed model used to exercise invokeAs.
class Greeting {
  Greeting(this.message);
  final String message;

  factory Greeting.fromJson(Map<String, dynamic> json) =>
      Greeting(json['message'] as String);
}

InsforgeHttpClient _clientWith(DioAdapter adapter) {
  final client = InsforgeHttpClient(
    baseUrl: 'https://x.insforge.app',
    anonKey: 'anon-123',
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  group('FunctionsClient errors', () {
    test('a 404 throws InsforgeHttpException with statusCode 404', () async {
      final dioAdapter = DioAdapter(dio: Dio());
      final client = _clientWith(dioAdapter);
      dioAdapter.onPost(
        '/functions/missing',
        (server) => server.reply(
          404,
          <String, dynamic>{'error': 'Function not found or not active'},
        ),
        data: <String, dynamic>{'x': 1},
      );

      final functions = FunctionsClient(client);

      await expectLater(
        () => functions.invoke('missing', body: <String, dynamic>{'x': 1}),
        throwsA(
          isA<InsforgeHttpException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.error,
                'error',
                'Function not found or not active',
              ),
        ),
      );
    });

    test('a 502 throws InsforgeHttpException with statusCode 502', () async {
      final dioAdapter = DioAdapter(dio: Dio());
      final client = _clientWith(dioAdapter);
      dioAdapter.onPost(
        '/functions/broken',
        (server) => server.reply(
          502,
          <String, dynamic>{'error': 'Failed to connect to Deno runtime'},
        ),
        data: null,
      );

      final functions = FunctionsClient(client);

      await expectLater(
        () => functions.invoke('broken'),
        throwsA(
          isA<InsforgeHttpException>()
              .having((e) => e.statusCode, 'statusCode', 502),
        ),
      );
    });
  });

  group('FunctionsClient.invokeAs', () {
    test('maps a JSON object response via fromJson', () async {
      final dioAdapter = DioAdapter(dio: Dio());
      final client = _clientWith(dioAdapter);
      dioAdapter.onPost(
        '/functions/hello-world',
        (server) => server.reply(
          200,
          <String, dynamic>{'message': 'Hello, Ada!'},
        ),
        data: <String, dynamic>{'name': 'Ada'},
      );

      final functions = FunctionsClient(client);

      final greeting = await functions.invokeAs<Greeting>(
        'hello-world',
        Greeting.fromJson,
        body: <String, dynamic>{'name': 'Ada'},
      );

      expect(greeting.message, 'Hello, Ada!');
    });

    test('throws InsforgeSerializationException for a non-object response',
        () async {
      final dioAdapter = DioAdapter(dio: Dio());
      final client = _clientWith(dioAdapter);
      dioAdapter.onPost(
        '/functions/numbers',
        (server) => server.reply(200, <int>[1, 2, 3]),
        data: null,
      );

      final functions = FunctionsClient(client);

      await expectLater(
        () => functions.invokeAs<Greeting>('numbers', Greeting.fromJson),
        throwsA(isA<InsforgeSerializationException>()),
      );
    });
  });
}
