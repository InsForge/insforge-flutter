import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

void main() {
  group('ChatCompletionResponse.fromJson', () {
    test('parses id, model, choices, and usage', () {
      final resp = ChatCompletionResponse.fromJson(<String, dynamic>{
        'id': 'chatcmpl-1',
        'model': 'openai/gpt-4o',
        'choices': <dynamic>[
          <String, dynamic>{
            'index': 0,
            'message': <String, dynamic>{
              'role': 'assistant',
              'content': 'Hello there.',
            },
            'finish_reason': 'stop',
          },
        ],
        'usage': <String, dynamic>{
          'prompt_tokens': 5,
          'completion_tokens': 7,
          'total_tokens': 12,
        },
      });

      expect(resp.id, 'chatcmpl-1');
      expect(resp.model, 'openai/gpt-4o');
      expect(resp.choices, hasLength(1));

      final choice = resp.choices.single;
      expect(choice.index, 0);
      expect(choice.finishReason, 'stop');
      expect(choice.message.role, 'assistant');
      expect(choice.message.content, 'Hello there.');

      expect(resp.usage?.totalTokens, 12);

      // Convenience accessor for the first choice's text.
      expect(resp.content, 'Hello there.');
    });

    test('parses tool_calls in the response message', () {
      final resp = ChatCompletionResponse.fromJson(<String, dynamic>{
        'id': 'chatcmpl-2',
        'model': 'm',
        'choices': <dynamic>[
          <String, dynamic>{
            'index': 0,
            'message': <String, dynamic>{
              'role': 'assistant',
              'content': null,
              'tool_calls': <dynamic>[
                <String, dynamic>{
                  'id': 'call_1',
                  'type': 'function',
                  'function': <String, dynamic>{
                    'name': 'get_weather',
                    'arguments': '{"city":"SF"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });

      final choice = resp.choices.single;
      expect(choice.finishReason, 'tool_calls');
      expect(choice.message.toolCalls, hasLength(1));
      expect(choice.message.toolCalls!.single.function.name, 'get_weather');
      expect(resp.usage, isNull);
    });
  });
}
