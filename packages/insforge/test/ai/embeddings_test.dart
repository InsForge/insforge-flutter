import 'package:dio/dio.dart';
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

void main() {
  group('Embeddings.create', () {
    test('serializes a single string input and parses vectors', () async {
      final dio = Dio();
      final adapter = RecordingAdapter(
        '{"object":"list","model":"openai/text-embedding-3-small",'
        '"data":[{"object":"embedding","index":0,'
        '"embedding":[0.1,0.2,0.3]}],'
        '"usage":{"prompt_tokens":4,"completion_tokens":0,"total_tokens":4}}',
      );
      dio.httpClientAdapter = adapter;
      final client = AIClient('sk-or-test', dio: dio);

      final resp = await client.embeddings.create(
        EmbeddingsRequest(
          model: 'openai/text-embedding-3-small',
          input: 'hello world',
          dimensions: 3,
        ),
      );

      final body = adapter.bodies.single;
      expect(adapter.paths.single, '/embeddings');
      expect(body['model'], 'openai/text-embedding-3-small');
      expect(body['input'], 'hello world');
      expect(body['dimensions'], 3);

      expect(resp.data, hasLength(1));
      expect(resp.data.single.index, 0);
      expect(resp.data.single.embedding, <double>[0.1, 0.2, 0.3]);
      expect(resp.usage?.promptTokens, 4);
    });

    test('serializes a list input and encoding_format', () async {
      final dio = Dio();
      final adapter = RecordingAdapter(
        '{"object":"list","model":"m","data":['
        '{"object":"embedding","index":0,"embedding":[0.5]},'
        '{"object":"embedding","index":1,"embedding":[0.6]}]}',
      );
      dio.httpClientAdapter = adapter;
      final client = AIClient('sk-or-test', dio: dio);

      final resp = await client.embeddings.create(
        EmbeddingsRequest(
          model: 'm',
          input: <String>['a', 'b'],
          encodingFormat: 'float',
        ),
      );

      final body = adapter.bodies.single;
      expect(body['input'], <String>['a', 'b']);
      expect(body['encoding_format'], 'float');

      expect(resp.data, hasLength(2));
      expect(resp.data[1].index, 1);
      expect(resp.data[1].embedding, <double>[0.6]);
      expect(resp.usage, isNull);
    });
  });
}
