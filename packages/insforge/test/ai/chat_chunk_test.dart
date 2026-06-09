import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

void main() {
  test('ChatCompletionChunk parses delta content', () {
    final chunk = ChatCompletionChunk.fromJson(<String, dynamic>{
      'id': 'chatcmpl-1',
      'model': 'm',
      'choices': <dynamic>[
        <String, dynamic>{
          'index': 0,
          'delta': <String, dynamic>{'content': 'Hel'},
          'finish_reason': null,
        },
      ],
    });
    expect(chunk.choices.single.delta.content, 'Hel');
    expect(chunk.choices.single.finishReason, isNull);

    // Convenience accessor for the first delta's content.
    expect(chunk.contentDelta, 'Hel');
  });

  test('ChatCompletionChunk tolerates an empty/absent delta content', () {
    final chunk = ChatCompletionChunk.fromJson(<String, dynamic>{
      'choices': <dynamic>[
        <String, dynamic>{
          'index': 0,
          'delta': <String, dynamic>{'role': 'assistant'},
          'finish_reason': 'stop',
        },
      ],
    });
    expect(chunk.choices.single.delta.content, isNull);
    expect(chunk.choices.single.finishReason, 'stop');
    expect(chunk.contentDelta, isNull);
  });
}
