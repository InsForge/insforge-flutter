import 'chat_message.dart';
import 'tool.dart';

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
