import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

void main() {
  group('Models.list', () {
    test('GETs /models and parses the data array', () async {
      final dio = Dio();
      final adapter = RecordingAdapter(
        '{"data":['
        '{"id":"openai/gpt-4o","name":"GPT-4o","context_length":128000},'
        '{"id":"anthropic/claude-3.5-sonnet","name":"Claude 3.5 Sonnet"}'
        ']}',
      );
      dio.httpClientAdapter = adapter;
      final client = AIClient('sk-or-test', dio: dio);

      final models = await client.models.list();

      expect(adapter.paths.single, '/models');
      expect(models, hasLength(2));
      expect(models.first.id, 'openai/gpt-4o');
      expect(models.first.name, 'GPT-4o');
      expect(models.first.contextLength, 128000);
      expect(models[1].id, 'anthropic/claude-3.5-sonnet');
      expect(models[1].contextLength, isNull);
    });
  });
}
