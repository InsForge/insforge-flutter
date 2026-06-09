import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

void main() {
  group('ChatMessage convenience constructors', () {
    test('user/.assistant/.system set role and string content', () {
      expect(ChatMessage.user('hi').role, 'user');
      expect(ChatMessage.user('hi').content, 'hi');
      expect(ChatMessage.assistant('yo').role, 'assistant');
      expect(ChatMessage.system('be terse').role, 'system');
    });

    test('a plain string message serializes content as a JSON string', () {
      final json = ChatMessage.user('hello').toJson();
      expect(json['role'], 'user');
      expect(json['content'], 'hello');
    });

    test('userWithImages builds a multimodal content array', () {
      final msg = ChatMessage.userWithImages(
        'What is in these images?',
        <String>['https://x.com/a.jpg', 'data:image/png;base64,AAAA'],
      );
      final json = msg.toJson();
      expect(json['role'], 'user');

      final content = json['content'] as List<dynamic>;
      expect(content, hasLength(3));

      expect(content[0], <String, dynamic>{
        'type': 'text',
        'text': 'What is in these images?',
      });
      expect(content[1], <String, dynamic>{
        'type': 'image_url',
        'image_url': <String, dynamic>{'url': 'https://x.com/a.jpg'},
      });
      expect(content[2], <String, dynamic>{
        'type': 'image_url',
        'image_url': <String, dynamic>{'url': 'data:image/png;base64,AAAA'},
      });
    });

    test('serializes tool_call_id under snake_case for tool messages', () {
      final msg = ChatMessage.tool(toolCallId: 'call_1', content: '42');
      final json = msg.toJson();
      expect(json['role'], 'tool');
      expect(json['content'], '42');
      expect(json['tool_call_id'], 'call_1');
    });

    test('parses a response message with tool_calls', () {
      final msg = ChatMessage.fromJson(<String, dynamic>{
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
      });
      expect(msg.role, 'assistant');
      expect(msg.toolCalls, hasLength(1));
      expect(msg.toolCalls!.single.function.name, 'get_weather');
    });
  });
}
