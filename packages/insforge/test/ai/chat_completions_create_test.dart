import 'package:dio/dio.dart';
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

void main() {
  group('ChatCompletions.create', () {
    test('POSTs snake_case body to /chat/completions and parses the response',
        () async {
      final dio = Dio();
      final adapter = RecordingAdapter(
        '{"id":"chatcmpl-1","model":"openai/gpt-4o",'
        '"choices":[{"index":0,"message":{"role":"assistant",'
        '"content":"Hi!"},"finish_reason":"stop"}],'
        '"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}',
      );
      dio.httpClientAdapter = adapter;
      final client = AIClient('sk-or-test', dio: dio);

      final resp = await client.chat.completions.create(
        ChatCompletionRequest(
          model: 'openai/gpt-4o',
          messages: <ChatMessage>[ChatMessage.user('hi')],
          maxTokens: 64,
          topP: 0.8,
        ),
      );

      // Request body is snake_case + stream:false.
      final body = adapter.bodies.single;
      expect(adapter.paths.single, '/chat/completions');
      expect(body['model'], 'openai/gpt-4o');
      expect(body['max_tokens'], 64);
      expect(body['top_p'], 0.8);
      expect(body['stream'], false);

      // Response parsed.
      expect(resp.id, 'chatcmpl-1');
      expect(resp.content, 'Hi!');
      expect(resp.choices.single.finishReason, 'stop');
      expect(resp.usage?.totalTokens, 5);
    });

    test('throws InsforgeHttpException with nested OpenRouter error', () async {
      final dio = Dio();
      dio.httpClientAdapter = RecordingAdapter(
        '{"error":{"message":"model is required","code":"invalid_request"}}',
        statusCode: 400,
      );
      final client = AIClient('sk-or-test', dio: dio);

      expect(
        () => client.chat.completions.create(
          ChatCompletionRequest(
            model: '',
            messages: <ChatMessage>[ChatMessage.user('hi')],
          ),
        ),
        throwsA(
          isA<InsforgeHttpException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', 'model is required')
              .having((e) => e.error, 'error', 'invalid_request'),
        ),
      );
    });
  });
}
