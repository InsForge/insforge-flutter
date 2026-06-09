import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

void main() {
  group('AIClient construction', () {
    test('defaults the base URL to OpenRouter', () {
      final client = AIClient('sk-or-test');
      expect(client.dio.options.baseUrl, 'https://openrouter.ai/api/v1');
    });

    test('sets the Authorization bearer header', () {
      final client = AIClient('sk-or-test');
      expect(
        client.dio.options.headers['Authorization'],
        'Bearer sk-or-test',
      );
    });

    test('adds HTTP-Referer and X-Title when provided', () {
      final client = AIClient(
        'sk-or-test',
        referer: 'https://myapp.example',
        title: 'My App',
      );
      expect(
        client.dio.options.headers['HTTP-Referer'],
        'https://myapp.example',
      );
      expect(client.dio.options.headers['X-Title'], 'My App');
    });

    test('omits ranking headers when not provided', () {
      final client = AIClient('sk-or-test');
      expect(client.dio.options.headers.containsKey('HTTP-Referer'), isFalse);
      expect(client.dio.options.headers.containsKey('X-Title'), isFalse);
    });

    test('uses an injected Dio', () {
      final dio = Dio();
      final client = AIClient('sk-or-test', dio: dio);
      expect(identical(client.dio, dio), isTrue);
      // Injected Dio is still configured with base URL + auth.
      expect(client.dio.options.baseUrl, 'https://openrouter.ai/api/v1');
      expect(client.dio.options.headers['Authorization'], 'Bearer sk-or-test');
    });

    test('sends the bearer header on a request (via injected adapter)',
        () async {
      final dio = Dio();
      final adapter = RecordingAdapter('{"id":"x","model":"m","choices":[]}');
      dio.httpClientAdapter = adapter;
      final client = AIClient('sk-or-test', dio: dio);

      await client.chat.completions.create(
        ChatCompletionRequest(
          model: 'm',
          messages: <ChatMessage>[ChatMessage.user('hi')],
        ),
      );

      expect(
        adapter.headers.single['Authorization'],
        <String>['Bearer sk-or-test'],
      );
      expect(adapter.paths.single, '/chat/completions');
    });
  });
}
