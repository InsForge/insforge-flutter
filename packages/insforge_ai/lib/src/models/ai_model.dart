/// A model entry from OpenRouter's `GET /models` list.
class AiModel {
  const AiModel({required this.id, this.name, this.contextLength});

  final String id;
  final String? name;
  final int? contextLength;

  factory AiModel.fromJson(Map<String, dynamic> json) => AiModel(
        id: (json['id'] ?? '').toString(),
        name: json['name']?.toString(),
        contextLength: (json['context_length'] as num?)?.toInt(),
      );
}
