import 'content_part.dart';
import 'tool.dart';

/// A single chat message.
///
/// [content] is a union: a plain [String] (the common case) or a
/// `List<ContentPart>` for multimodal messages. It may be `null` for an
/// assistant message that only carries [toolCalls].
class ChatMessage {
  const ChatMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
  });

  /// One of `user`, `assistant`, `system`, `tool`.
  final String role;

  /// A `String` or a `List<ContentPart>` (or `null`).
  final Object? content;

  final List<ToolCall>? toolCalls;
  final String? toolCallId;

  /// A user message with plain text.
  factory ChatMessage.user(String content) =>
      ChatMessage(role: 'user', content: content);

  /// An assistant message with plain text.
  factory ChatMessage.assistant(String content) =>
      ChatMessage(role: 'assistant', content: content);

  /// A system message with plain text.
  factory ChatMessage.system(String content) =>
      ChatMessage(role: 'system', content: content);

  /// A tool-result message responding to a prior tool call.
  factory ChatMessage.tool({
    required String toolCallId,
    required String content,
  }) =>
      ChatMessage(role: 'tool', content: content, toolCallId: toolCallId);

  /// A user message combining text and one or more images
  /// (public URLs or `data:` base64 URIs).
  factory ChatMessage.userWithImages(String text, List<String> imageUrls) {
    final parts = <ContentPart>[
      TextPart(text),
      for (final url in imageUrls) ImageUrlPart(url),
    ];
    return ChatMessage(role: 'user', content: parts);
  }

  Map<String, dynamic> toJson() {
    final Object? serializedContent;
    final c = content;
    if (c is List<ContentPart>) {
      serializedContent = c.map((p) => p.toJson()).toList();
    } else {
      serializedContent = c; // String or null
    }
    return <String, dynamic>{
      'role': role,
      'content': serializedContent,
      if (toolCalls != null)
        'tool_calls': toolCalls!.map((t) => t.toJson()).toList(),
      if (toolCallId != null) 'tool_call_id': toolCallId,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawContent = json['content'];
    final Object? content;
    if (rawContent is List) {
      content = rawContent
          .whereType<Map<String, dynamic>>()
          .map(ContentPart.fromJson)
          .toList();
    } else {
      content = rawContent; // String or null
    }
    final rawToolCalls = json['tool_calls'];
    return ChatMessage(
      role: (json['role'] ?? 'assistant').toString(),
      content: content,
      toolCalls: rawToolCalls is List
          ? rawToolCalls
              .whereType<Map<String, dynamic>>()
              .map(ToolCall.fromJson)
              .toList()
          : null,
      toolCallId: json['tool_call_id']?.toString(),
    );
  }
}
