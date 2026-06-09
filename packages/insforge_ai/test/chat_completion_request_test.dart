import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

void main() {
  group('ChatCompletionRequest.toJson', () {
    test('serializes optional fields to snake_case and defaults stream=false',
        () {
      final req = ChatCompletionRequest(
        model: 'openai/gpt-4o',
        messages: <ChatMessage>[ChatMessage.user('hello')],
        temperature: 0.7,
        maxTokens: 256,
        topP: 0.9,
      );
      final json = req.toJson();

      expect(json['model'], 'openai/gpt-4o');
      expect(json['temperature'], 0.7);
      expect(json['max_tokens'], 256);
      expect(json['top_p'], 0.9);
      expect(json['stream'], false);
      expect(
        (json['messages'] as List<dynamic>).single,
        <String, dynamic>{'role': 'user', 'content': 'hello'},
      );
    });

    test('omits null optionals', () {
      final req = ChatCompletionRequest(
        model: 'm',
        messages: <ChatMessage>[ChatMessage.user('x')],
      );
      final json = req.toJson();
      expect(json.containsKey('temperature'), isFalse);
      expect(json.containsKey('max_tokens'), isFalse);
      expect(json.containsKey('top_p'), isFalse);
      expect(json.containsKey('tools'), isFalse);
      expect(json.containsKey('tool_choice'), isFalse);
    });

    test('serializes tools and tool_choice', () {
      final req = ChatCompletionRequest(
        model: 'm',
        messages: <ChatMessage>[ChatMessage.user('x')],
        tools: <Tool>[
          Tool(
            function: ToolFunction(
              name: 'get_weather',
              parameters: <String, dynamic>{'type': 'object'},
            ),
          ),
        ],
        toolChoice: ToolChoice.function('get_weather'),
      );
      final json = req.toJson();

      final tools = json['tools'] as List<dynamic>;
      expect((tools.single as Map<String, dynamic>)['type'], 'function');

      expect(json['tool_choice'], <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{'name': 'get_weather'},
      });
    });

    test('serializes a bare-string tool_choice', () {
      final req = ChatCompletionRequest(
        model: 'm',
        messages: <ChatMessage>[ChatMessage.user('x')],
        toolChoice: ToolChoice.auto,
      );
      expect(req.toJson()['tool_choice'], 'auto');
    });
  });

  group('Usage.fromJson', () {
    test('parses token counts', () {
      final usage = Usage.fromJson(<String, dynamic>{
        'prompt_tokens': 10,
        'completion_tokens': 20,
        'total_tokens': 30,
      });
      expect(usage.promptTokens, 10);
      expect(usage.completionTokens, 20);
      expect(usage.totalTokens, 30);
    });
  });
}
