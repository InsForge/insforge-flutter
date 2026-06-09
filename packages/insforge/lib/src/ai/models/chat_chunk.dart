import 'tool.dart';

/// The incremental delta inside a streaming choice.
class Delta {
  const Delta({this.role, this.content, this.toolCalls});

  final String? role;
  final String? content;
  final List<ToolCall>? toolCalls;

  factory Delta.fromJson(Map<String, dynamic> json) {
    final rawToolCalls = json['tool_calls'];
    return Delta(
      role: json['role']?.toString(),
      content: json['content']?.toString(),
      toolCalls: rawToolCalls is List
          ? rawToolCalls
              .whereType<Map<String, dynamic>>()
              .map(ToolCall.fromJson)
              .toList()
          : null,
    );
  }
}

/// A single choice within a streaming chunk.
class ChunkChoice {
  const ChunkChoice({
    required this.index,
    required this.delta,
    this.finishReason,
  });

  final int index;
  final Delta delta;
  final String? finishReason;

  factory ChunkChoice.fromJson(Map<String, dynamic> json) {
    final rawDelta = json['delta'];
    return ChunkChoice(
      index: (json['index'] as num?)?.toInt() ?? 0,
      delta: rawDelta is Map<String, dynamic>
          ? Delta.fromJson(rawDelta)
          : const Delta(),
      finishReason: json['finish_reason']?.toString(),
    );
  }
}

/// One streamed `chat.completion.chunk` event.
class ChatCompletionChunk {
  const ChatCompletionChunk({
    required this.id,
    required this.model,
    required this.choices,
  });

  final String id;
  final String model;
  final List<ChunkChoice> choices;

  /// Convenience accessor for the first choice's delta content.
  String? get contentDelta =>
      choices.isEmpty ? null : choices.first.delta.content;

  factory ChatCompletionChunk.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'];
    return ChatCompletionChunk(
      id: (json['id'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      choices: rawChoices is List
          ? rawChoices
              .whereType<Map<String, dynamic>>()
              .map(ChunkChoice.fromJson)
              .toList()
          : <ChunkChoice>[],
    );
  }
}
