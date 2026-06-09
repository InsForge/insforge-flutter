import 'package:dio/dio.dart';
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

void main() {
  group('Images.generate', () {
    test('sends a chat request with image modalities and parses data URLs',
        () async {
      final dio = Dio();
      final adapter = RecordingAdapter(
        '{"id":"x","model":"google/gemini-2.5-flash-image",'
        '"choices":[{"index":0,"message":{"role":"assistant",'
        '"content":"Here you go.","images":[{"image_url":'
        '{"url":"data:image/png;base64,AAAABBBB"}}]},'
        '"finish_reason":"stop"}]}',
      );
      dio.httpClientAdapter = adapter;
      final client = AIClient('sk-or-test', dio: dio);

      final resp = await client.images.generate(
        ImageGenerationRequest(
          model: 'google/gemini-2.5-flash-image',
          prompt: 'a sunset over mountains',
        ),
      );

      // Routed through /chat/completions with modalities.
      final body = adapter.bodies.single;
      expect(adapter.paths.single, '/chat/completions');
      expect(body['model'], 'google/gemini-2.5-flash-image');
      expect(body['modalities'], <String>['image', 'text']);
      final messages = body['messages'] as List<dynamic>;
      expect(
        (messages.single as Map<String, dynamic>)['content'],
        'a sunset over mountains',
      );

      // Response adapted into OpenAI-compatible shape.
      expect(resp.data, hasLength(1));
      expect(resp.data.single.url, 'data:image/png;base64,AAAABBBB');
      expect(resp.data.single.b64Json, 'AAAABBBB');
    });

    test('returns empty data when the model produced no images', () async {
      final dio = Dio();
      dio.httpClientAdapter = RecordingAdapter(
        '{"id":"x","model":"m","choices":[{"index":0,'
        '"message":{"role":"assistant","content":"no image"},'
        '"finish_reason":"stop"}]}',
      );
      final client = AIClient('sk-or-test', dio: dio);

      final resp = await client.images.generate(
        ImageGenerationRequest(model: 'm', prompt: 'x'),
      );
      expect(resp.data, isEmpty);
    });
  });
}
