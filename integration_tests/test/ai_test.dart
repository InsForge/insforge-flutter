// integration_tests/test/ai_test.dart
//
// AI module integration tests. The AI client is a STANDALONE OpenRouter
// (OpenAI-compatible) client — it does NOT route through InsForge — so it only
// needs an OpenRouter API key (aiConfigured).
//
// When a model is unavailable/disabled the API throws; those errors are
// caught (mirroring the JS `isModelUnavailable`) and the test is marked
// skipped rather than masking a real assertion failure.
import 'package:insforge_ai/insforge_ai.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

const String _chatModel = 'openai/gpt-4o-mini';
const String _embeddingsModel = 'openai/text-embedding-3-small';

/// True when [err] indicates the model is unavailable/disabled (not a real
/// failure of the SDK).
bool _isModelUnavailable(Object err) {
  final msg = err.toString().toLowerCase();
  String? code;
  if (err is InsforgeHttpException) {
    code = err.error?.toLowerCase();
  }
  return code == 'model_not_found' ||
      msg.contains('not available') ||
      msg.contains('unavailable') ||
      msg.contains('disabled') ||
      msg.contains('not enabled') ||
      msg.contains('model not found') ||
      msg.contains('not supported');
}

void main() {
  group(
    'AI Module',
    () {
      late AIClient ai;

      setUpAll(() {
        ai = AIClient(env.openRouterKey!);
      });

      test('models.list returns a non-empty list', () async {
        final models = await ai.models.list();
        expect(models, isNotEmpty);
        expect(models.first.id, isNotEmpty);
      });

      test('chat.completions.create returns a choice', () async {
        ChatCompletionResponse response;
        try {
          response = await ai.chat.completions.create(
            ChatCompletionRequest(
              model: _chatModel,
              messages: <ChatMessage>[
                ChatMessage.user('Reply with exactly the word: pong'),
              ],
              maxTokens: 16,
            ),
          );
        } catch (e) {
          if (_isModelUnavailable(e)) {
            markTestSkipped('Chat model unavailable: $e');
            return;
          }
          rethrow;
        }

        expect(response.choices, isNotEmpty);
        expect(response.choices.first.message.role, 'assistant');
        expect(response.choices.first.message.content, isNotNull);
        expect(response.choices.first.message.content, isNotEmpty);
      });

      test('chat.completions.create supports system messages', () async {
        ChatCompletionResponse response;
        try {
          response = await ai.chat.completions.create(
            ChatCompletionRequest(
              model: _chatModel,
              messages: <ChatMessage>[
                ChatMessage.system(
                  'You are a calculator. Reply with only numbers.',
                ),
                ChatMessage.user('What is 2 + 2?'),
              ],
              maxTokens: 16,
            ),
          );
        } catch (e) {
          if (_isModelUnavailable(e)) {
            markTestSkipped('Chat model unavailable: $e');
            return;
          }
          rethrow;
        }
        expect(response.choices.first.message.content, isNotNull);
      });

      test('createStream yields at least one chunk', () async {
        Stream<ChatCompletionChunk> stream;
        try {
          stream = ai.chat.completions.createStream(
            ChatCompletionRequest(
              model: _chatModel,
              messages: <ChatMessage>[
                ChatMessage.user('Count from 1 to 5, separated by commas.'),
              ],
              maxTokens: 32,
            ),
          );
        } catch (e) {
          if (_isModelUnavailable(e)) {
            markTestSkipped('Streaming unavailable: $e');
            return;
          }
          rethrow;
        }

        var chunkCount = 0;
        final buffer = StringBuffer();
        try {
          await for (final chunk in stream) {
            chunkCount++;
            final delta = chunk.contentDelta;
            if (delta != null) buffer.write(delta);
          }
        } catch (e) {
          if (_isModelUnavailable(e)) {
            markTestSkipped('Streaming unavailable: $e');
            return;
          }
          rethrow;
        }

        expect(chunkCount, greaterThanOrEqualTo(1));
      });

      test('embeddings.create for a short string', () async {
        EmbeddingsResponse response;
        try {
          response = await ai.embeddings.create(
            const EmbeddingsRequest(
              model: _embeddingsModel,
              input: 'Hello world',
            ),
          );
        } catch (e) {
          if (_isModelUnavailable(e)) {
            markTestSkipped('Embeddings model unavailable: $e');
            return;
          }
          rethrow;
        }

        expect(response.data, hasLength(1));
        expect(response.data.first.index, 0);
        expect(response.data.first.embedding, isNotEmpty);
      });
    },
    skip: env.aiSkipReason,
  );
}
