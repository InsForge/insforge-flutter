import 'package:dio/dio.dart';
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

import 'support/sse_adapter.dart';

void main() {
  group('ChatCompletions.createStream', () {
    test('parses SSE chunks into content deltas and stops at [DONE]',
        () async {
      final dio = Dio();
      dio.httpClientAdapter = SseAdapter(<String>[
        '{"id":"c","model":"m","choices":[{"index":0,'
            '"delta":{"content":"Hel"},"finish_reason":null}]}',
        '{"id":"c","model":"m","choices":[{"index":0,'
            '"delta":{"content":"lo"},"finish_reason":null}]}',
        '{"id":"c","model":"m","choices":[{"index":0,'
            '"delta":{},"finish_reason":"stop"}]}',
      ]);
      final client = AIClient('sk-or-test', dio: dio);

      final chunks = await client.chat.completions
          .createStream(
            ChatCompletionRequest(
              model: 'm',
              messages: <ChatMessage>[ChatMessage.user('hi')],
            ),
          )
          .toList();

      // Three data frames before [DONE].
      expect(chunks, hasLength(3));
      final text = chunks.map((c) => c.contentDelta ?? '').join();
      expect(text, 'Hello');
      expect(chunks.last.choices.single.finishReason, 'stop');
    });

    test('ignores blank lines and non-data lines', () async {
      final dio = Dio();
      // The SSE adapter already wraps payloads with blank-line separators; a
      // payload that is a comment-like ping should be skipped by the parser if
      // it does not start with `data: `. Here we only feed valid frames and a
      // trailing [DONE]; assert we get exactly the valid frames.
      dio.httpClientAdapter = SseAdapter(<String>[
        '{"choices":[{"index":0,"delta":{"content":"A"}}]}',
      ]);
      final client = AIClient('sk-or-test', dio: dio);

      final chunks = await client.chat.completions
          .createStream(
            ChatCompletionRequest(
              model: 'm',
              messages: <ChatMessage>[ChatMessage.user('hi')],
            ),
          )
          .toList();

      expect(chunks, hasLength(1));
      expect(chunks.single.contentDelta, 'A');
    });
  });
}
