import 'usage.dart';

/// An OpenAI/OpenRouter-compatible embeddings request.
///
/// [input] is a union: a `String` (single) or `List<String>` (batch). It is
/// serialized as a JSON string or array accordingly.
class EmbeddingsRequest {
  const EmbeddingsRequest({
    required this.model,
    required this.input,
    this.encodingFormat,
    this.dimensions,
  })  : assert(
          input is String || input is List<String>,
          'input must be a String or List<String>',
        );

  final String model;

  /// A `String` or `List<String>`.
  final Object input;
  final String? encodingFormat;
  final int? dimensions;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'model': model,
        'input': input,
        if (encodingFormat != null) 'encoding_format': encodingFormat,
        if (dimensions != null) 'dimensions': dimensions,
      };
}

/// One embedding vector with its position in the input batch.
class EmbeddingData {
  const EmbeddingData({required this.embedding, required this.index});

  final List<double> embedding;
  final int index;

  factory EmbeddingData.fromJson(Map<String, dynamic> json) {
    final rawEmbedding = json['embedding'];
    return EmbeddingData(
      embedding: rawEmbedding is List
          ? rawEmbedding
              .map((e) => (e as num).toDouble())
              .toList(growable: false)
          : <double>[],
      index: (json['index'] as num?)?.toInt() ?? 0,
    );
  }
}

/// An OpenAI/OpenRouter-compatible embeddings response.
class EmbeddingsResponse {
  const EmbeddingsResponse({
    required this.data,
    required this.model,
    this.usage,
  });

  final List<EmbeddingData> data;
  final String model;
  final Usage? usage;

  factory EmbeddingsResponse.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final rawUsage = json['usage'];
    return EmbeddingsResponse(
      data: rawData is List
          ? rawData
              .whereType<Map<String, dynamic>>()
              .map(EmbeddingData.fromJson)
              .toList()
          : <EmbeddingData>[],
      model: (json['model'] ?? '').toString(),
      usage: rawUsage is Map<String, dynamic> ? Usage.fromJson(rawUsage) : null,
    );
  }
}
