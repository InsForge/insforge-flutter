import 'chat_message.dart';
import 'tool.dart';
import 'usage.dart';

/// An OpenAI/OpenRouter-compatible chat completion request.
///
/// Serializes to strict snake_case (`max_tokens`, `top_p`, `tool_choice`).
class ChatCompletionRequest {
  const ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.temperature,
    this.maxTokens,
    this.topP,
    this.stream = false,
    this.tools,
    this.toolChoice,
  });

  final String model;
  final List<ChatMessage> messages;
  final double? temperature;
  final int? maxTokens;
  final double? topP;
  final bool stream;
  final List<Tool>? tools;
  final ToolChoice? toolChoice;

  /// Builds the JSON body. [streamOverride] lets the client force
  /// `stream: true` for [ChatCompletions.createStream] without the caller
  /// having to mutate the request.
  Map<String, dynamic> toJson({bool? streamOverride}) => <String, dynamic>{
        'model': model,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (temperature != null) 'temperature': temperature,
        if (maxTokens != null) 'max_tokens': maxTokens,
        if (topP != null) 'top_p': topP,
        'stream': streamOverride ?? stream,
        if (tools != null) 'tools': tools!.map((t) => t.toJson()).toList(),
        if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
      };
}

/// The message inside a non-streaming completion choice.
class ResponseMessage {
  const ResponseMessage({
    required this.role,
    this.content,
    this.toolCalls,
  });

  final String role;
  final String? content;
  final List<ToolCall>? toolCalls;

  factory ResponseMessage.fromJson(Map<String, dynamic> json) {
    final rawToolCalls = json['tool_calls'];
    return ResponseMessage(
      role: (json['role'] ?? 'assistant').toString(),
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

/// A single completion choice.
class Choice {
  const Choice({
    required this.index,
    required this.message,
    this.finishReason,
  });

  final int index;
  final ResponseMessage message;
  final String? finishReason;

  factory Choice.fromJson(Map<String, dynamic> json) => Choice(
        index: (json['index'] as num?)?.toInt() ?? 0,
        message:
            ResponseMessage.fromJson(json['message'] as Map<String, dynamic>),
        finishReason: json['finish_reason']?.toString(),
      );
}

/// An OpenAI/OpenRouter-compatible chat completion response.
class ChatCompletionResponse {
  const ChatCompletionResponse({
    required this.id,
    required this.model,
    required this.choices,
    this.usage,
  });

  final String id;
  final String model;
  final List<Choice> choices;
  final Usage? usage;

  /// Convenience accessor for the first choice's text content.
  String? get content => choices.isEmpty ? null : choices.first.message.content;

  factory ChatCompletionResponse.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'];
    final rawUsage = json['usage'];
    return ChatCompletionResponse(
      id: (json['id'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      choices: rawChoices is List
          ? rawChoices
              .whereType<Map<String, dynamic>>()
              .map(Choice.fromJson)
              .toList()
          : <Choice>[],
      usage: rawUsage is Map<String, dynamic> ? Usage.fromJson(rawUsage) : null,
    );
  }
}
