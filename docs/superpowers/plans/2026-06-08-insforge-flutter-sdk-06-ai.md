# InsForge Flutter SDK — Plan 6: `insforge_ai` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart `insforge_ai` package: a **standalone** OpenRouter (OpenAI-compatible) client. It talks **directly** to OpenRouter (`https://openrouter.ai/api/v1`), not the InsForge proxy. It exposes OpenAI-ergonomic sub-namespaces (`chat.completions`, `images`, `embeddings`, `models`), hand-written `fromJson`/`toJson` models (no build_runner), SSE streaming for chat, and a local OpenRouter error mapper. It depends on `insforge_core` only for the shared exception types.

**Architecture:** `AIClient` owns its **own** `dio.Dio` pointed at OpenRouter (or an injected `Dio` for tests), with `Authorization: Bearer <openRouterApiKey>` and optional OpenRouter ranking headers (`HTTP-Referer`, `X-Title`). It is decoupled from `InsforgeHttpClient` — no auth-token store, no 401 refresh; OpenRouter keys are static. Requests serialize to OpenAI snake_case (`max_tokens`, `top_p`, `tool_choice`, `encoding_format`). Non-streaming calls parse the standard OpenAI response envelope; `createStream` consumes the SSE `data:` lines over `ResponseType.stream` and yields `ChatCompletionChunk`s. Image generation is routed through `/chat/completions` with `modalities: ['image','text']` (OpenRouter's image-capable models return base64 data URLs in `message.images[].image_url.url`), surfaced through an OpenAI-compatible `ImageGenerationResponse`. Transport/HTTP errors map through a **local** `mapOpenRouterError` that understands OpenRouter's **nested** `{"error": {"message": ..., "code": ...}}` envelope (the core `ErrorResponse.fromJson` expects a flat shape, so a local mapper is required).

**Tech Stack:** Dart ≥ 3.5 (pub workspaces), `dio` ^5.7.0, `meta` ^1.15.0, `insforge_core` (path dep, for shared exceptions only), `test`, `http_mock_adapter`, `lints`.

**Prerequisite:** The Flutter SDK (which bundles Dart) must be installed and on `PATH` (`dart --version` must work). Plan 1 (`insforge_core`) must already be implemented and present in the workspace (this package imports `package:insforge_core/insforge_core.dart` for `InsforgeException`, `InsforgeHttpException`, `InsforgeNetworkException`, `InsforgeSerializationException`).

**Plan series:** This is plan 6 of 7. It is independent of plans 2-5 and can be built any time after Plan 1. Plan 7 (umbrella + sample) wires `insforge_ai` in when an OpenRouter key is provided.

---

## File Structure

```
insforge-flutter/
├── pubspec.yaml                              # MODIFIED: append packages/insforge_ai to workspace list
└── packages/
    └── insforge_ai/
        ├── pubspec.yaml
        ├── analysis_options.yaml             # includes root lints
        ├── lib/
        │   ├── insforge_ai.dart              # public exports
        │   └── src/
        │       ├── errors.dart               # mapOpenRouterError (nested envelope)
        │       ├── models/
        │       │   ├── content_part.dart     # ContentPart, TextPart, ImageUrlPart
        │       │   ├── chat_message.dart     # ChatMessage + convenience ctors
        │       │   ├── tool.dart             # Tool, ToolFunction, ToolCall, ToolChoice
        │       │   ├── usage.dart            # Usage
        │       │   ├── chat_completion.dart  # ChatCompletionRequest/Response, Choice, ResponseMessage
        │       │   ├── chat_chunk.dart       # ChatCompletionChunk, ChunkChoice, Delta
        │       │   ├── images.dart           # ImageGenerationRequest/Response, GeneratedImage
        │       │   ├── embeddings.dart       # EmbeddingsRequest/Response, EmbeddingData
        │       │   └── ai_model.dart         # AiModel
        │       ├── chat_completions.dart     # ChatCompletions (create + createStream)
        │       ├── images_api.dart           # Images (generate)
        │       ├── embeddings_api.dart       # Embeddings (create)
        │       ├── models_api.dart           # Models (list)
        │       └── ai_client.dart            # AIClient + Chat namespace
        └── test/
            ├── support/recording_adapter.dart   # records request body; returns canned JSON
            ├── support/sse_adapter.dart          # streams data: lines for SSE tests
            ├── errors_test.dart
            ├── chat_message_test.dart
            ├── chat_completion_request_test.dart
            ├── chat_completion_response_test.dart
            ├── chat_completions_create_test.dart
            ├── chat_completions_stream_test.dart
            ├── images_test.dart
            ├── embeddings_test.dart
            └── models_test.dart
```

---

## Task 1: Package scaffolding

**Files:**
- Create: `packages/insforge_ai/pubspec.yaml`
- Create: `packages/insforge_ai/analysis_options.yaml`
- Create: `packages/insforge_ai/lib/insforge_ai.dart`
- Modify: `pubspec.yaml` (workspace root)

- [ ] **Step 1: Create the package `pubspec.yaml`**

```yaml
# packages/insforge_ai/pubspec.yaml
name: insforge_ai
description: Standalone OpenRouter (OpenAI-compatible) AI client for the InsForge Flutter SDK — chat, streaming, images, embeddings, models.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.5.0

dependencies:
  dio: ^5.7.0
  meta: ^1.15.0
  insforge_core:
    path: ../insforge_core

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  http_mock_adapter: ^0.6.1
```

- [ ] **Step 2: Create the package-local `analysis_options.yaml`**

```yaml
# packages/insforge_ai/analysis_options.yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 3: Append the package to the workspace root `pubspec.yaml`**

In the root `pubspec.yaml`, add `- packages/insforge_ai` to the `workspace:` list. After editing, the list should look like (other members may already be present from earlier plans):

```yaml
workspace:
  - packages/insforge_core
  - packages/insforge_ai
```

- [ ] **Step 4: Create a placeholder library export file**

```dart
// packages/insforge_ai/lib/insforge_ai.dart
/// Standalone OpenRouter (OpenAI-compatible) AI client.
library insforge_ai;

// Exports are added as each component lands in later tasks.
```

- [ ] **Step 5: Resolve dependencies**

Run: `dart pub get` (from repo root)
Expected: resolves the workspace including `insforge_ai`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/insforge_ai/pubspec.yaml packages/insforge_ai/analysis_options.yaml packages/insforge_ai/lib/insforge_ai.dart
git commit -m "feat(ai): add insforge_ai package skeleton"
```

---

## Task 2: Local OpenRouter error mapper

**Files:**
- Create: `packages/insforge_ai/lib/src/errors.dart`
- Test: `packages/insforge_ai/test/errors_test.dart`
- Modify: `packages/insforge_ai/lib/insforge_ai.dart`

OpenRouter returns a **nested** error envelope: `{"error": {"message": "...", "code": 400}}`. The core `ErrorResponse.fromJson` expects a flat shape, so we map locally.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_ai/test/errors_test.dart
import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  RequestOptions reqOptions() => RequestOptions(path: '/chat/completions');

  group('mapOpenRouterError', () {
    test('maps a nested {error:{message,code}} body to InsforgeHttpException',
        () {
      final err = DioException(
        requestOptions: reqOptions(),
        response: Response<dynamic>(
          requestOptions: reqOptions(),
          statusCode: 400,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'message': 'model is required',
              'code': 'invalid_request',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final mapped = mapOpenRouterError(err);
      expect(mapped, isA<InsforgeHttpException>());
      final http = mapped as InsforgeHttpException;
      expect(http.statusCode, 400);
      expect(http.message, 'model is required');
      expect(http.error, 'invalid_request');
    });

    test('falls back to the HTTP status code as error when code is an int', () {
      final err = DioException(
        requestOptions: reqOptions(),
        response: Response<dynamic>(
          requestOptions: reqOptions(),
          statusCode: 402,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'message': 'Insufficient credits',
              'code': 402,
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final http = mapOpenRouterError(err) as InsforgeHttpException;
      expect(http.statusCode, 402);
      expect(http.message, 'Insufficient credits');
      expect(http.error, '402');
    });

    test('tolerates a flat error string body', () {
      final err = DioException(
        requestOptions: reqOptions(),
        response: Response<dynamic>(
          requestOptions: reqOptions(),
          statusCode: 500,
          data: 'Internal Server Error',
        ),
        type: DioExceptionType.badResponse,
      );

      final http = mapOpenRouterError(err) as InsforgeHttpException;
      expect(http.statusCode, 500);
      expect(http.message, 'Internal Server Error');
    });

    test('maps timeouts to InsforgeNetworkException', () {
      final err = DioException(
        requestOptions: reqOptions(),
        type: DioExceptionType.receiveTimeout,
        message: 'timed out',
      );
      expect(mapOpenRouterError(err), isA<InsforgeNetworkException>());
    });

    test('maps connection errors to InsforgeNetworkException', () {
      final err = DioException(
        requestOptions: reqOptions(),
        type: DioExceptionType.connectionError,
        message: 'no connection',
      );
      expect(mapOpenRouterError(err), isA<InsforgeNetworkException>());
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/errors_test.dart`
Expected: FAIL — `mapOpenRouterError` is not defined.

- [ ] **Step 3: Write `errors.dart`**

```dart
// packages/insforge_ai/lib/src/errors.dart
import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';

/// Maps a [DioException] from the OpenRouter API to an [InsforgeException].
///
/// OpenRouter returns a **nested** error envelope:
/// `{"error": {"message": "...", "code": 400}}`. The core `ErrorResponse`
/// expects a flat shape, so this package maps it locally.
InsforgeException mapOpenRouterError(DioException e) {
  final response = e.response;
  if (response != null) {
    final statusCode = response.statusCode ?? -1;
    final data = response.data;

    String message = 'HTTP $statusCode';
    String? errorCode;

    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        message = (error['message'] ?? error['type'] ?? message).toString();
        final code = error['code'] ?? error['type'];
        errorCode = code?.toString();
      } else if (error != null) {
        message = error.toString();
      } else if (data['message'] != null) {
        message = data['message'].toString();
      }
    } else if (data is String && data.isNotEmpty) {
      message = data;
    }

    return InsforgeHttpException(
      statusCode: statusCode,
      message: message,
      error: errorCode,
      cause: e,
    );
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return InsforgeNetworkException(e.message ?? 'Network error', cause: e);
    default:
      return InsforgeException(e.message ?? 'Unknown error', cause: e);
  }
}
```

- [ ] **Step 4: Export it**

Replace the trailing comment in `packages/insforge_ai/lib/insforge_ai.dart` with:

```dart
export 'src/errors.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_ai && dart test test/errors_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_ai/lib/src/errors.dart packages/insforge_ai/lib/insforge_ai.dart packages/insforge_ai/test/errors_test.dart
git commit -m "feat(ai): add local OpenRouter (nested) error mapper"
```

---

## Task 3: Content parts (text + image_url)

**Files:**
- Create: `packages/insforge_ai/lib/src/models/content_part.dart`
- Modify: `packages/insforge_ai/lib/insforge_ai.dart`

These are plain value types exercised by the `ChatMessage` test in Task 4 (which asserts the multimodal content array). No dedicated test needed here.

- [ ] **Step 1: Write `content_part.dart`**

```dart
// packages/insforge_ai/lib/src/models/content_part.dart

/// A single part of a multimodal message content array.
///
/// OpenAI/OpenRouter content parts are tagged objects with a `type`
/// discriminator: `{type: 'text', text: ...}` or
/// `{type: 'image_url', image_url: {url: ...}}`.
abstract class ContentPart {
  const ContentPart();

  Map<String, dynamic> toJson();

  /// Parses a content-part object by its `type` discriminator.
  factory ContentPart.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'text':
        return TextPart.fromJson(json);
      case 'image_url':
        return ImageUrlPart.fromJson(json);
      default:
        // Unknown part types degrade to their text field when present.
        return TextPart((json['text'] ?? '').toString());
    }
  }
}

/// A plain-text content part: `{type: 'text', text: ...}`.
class TextPart extends ContentPart {
  const TextPart(this.text);

  final String text;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'text',
        'text': text,
      };

  factory TextPart.fromJson(Map<String, dynamic> json) =>
      TextPart((json['text'] ?? '').toString());
}

/// An image content part: `{type: 'image_url', image_url: {url: ...}}`.
///
/// [url] may be a public URL or a base64 data URI
/// (`data:image/jpeg;base64,...`).
class ImageUrlPart extends ContentPart {
  const ImageUrlPart(this.url);

  final String url;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'image_url',
        'image_url': <String, dynamic>{'url': url},
      };

  factory ImageUrlPart.fromJson(Map<String, dynamic> json) {
    final imageUrl = json['image_url'];
    final url = imageUrl is Map<String, dynamic>
        ? (imageUrl['url'] ?? '').toString()
        : '';
    return ImageUrlPart(url);
  }
}
```

- [ ] **Step 2: Export it**

Append to `packages/insforge_ai/lib/insforge_ai.dart`:

```dart
export 'src/models/content_part.dart';
```

- [ ] **Step 3: Analyze**

Run: `cd packages/insforge_ai && dart analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add packages/insforge_ai/lib/src/models/content_part.dart packages/insforge_ai/lib/insforge_ai.dart
git commit -m "feat(ai): add ContentPart (text/image_url) models"
```

---

## Task 4: Tool models (Tool, ToolCall, ToolChoice)

**Files:**
- Create: `packages/insforge_ai/lib/src/models/tool.dart`
- Modify: `packages/insforge_ai/lib/insforge_ai.dart`

Plain value types serialized inside the request; exercised by the request test in Task 6. No dedicated test needed.

- [ ] **Step 1: Write `tool.dart`**

```dart
// packages/insforge_ai/lib/src/models/tool.dart

/// A function definition exposed to the model as a callable tool.
class ToolFunction {
  const ToolFunction({
    required this.name,
    this.description,
    this.parameters,
  });

  final String name;
  final String? description;

  /// JSON-Schema object describing the function parameters.
  final Map<String, dynamic>? parameters;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        if (description != null) 'description': description,
        if (parameters != null) 'parameters': parameters,
      };

  factory ToolFunction.fromJson(Map<String, dynamic> json) => ToolFunction(
        name: json['name'].toString(),
        description: json['description']?.toString(),
        parameters: json['parameters'] is Map<String, dynamic>
            ? json['parameters'] as Map<String, dynamic>
            : null,
      );
}

/// A tool the model may call. Currently OpenAI/OpenRouter only define
/// `type: 'function'`.
class Tool {
  const Tool({required this.function, this.type = 'function'});

  final String type;
  final ToolFunction function;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type,
        'function': function.toJson(),
      };

  factory Tool.fromJson(Map<String, dynamic> json) => Tool(
        type: (json['type'] ?? 'function').toString(),
        function:
            ToolFunction.fromJson(json['function'] as Map<String, dynamic>),
      );
}

/// The function name + JSON-string arguments the model decided to call.
class ToolCallFunction {
  const ToolCallFunction({required this.name, required this.arguments});

  final String name;

  /// Arguments serialized as a JSON string (per OpenAI's contract).
  final String arguments;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'arguments': arguments,
      };

  factory ToolCallFunction.fromJson(Map<String, dynamic> json) =>
      ToolCallFunction(
        name: (json['name'] ?? '').toString(),
        arguments: (json['arguments'] ?? '').toString(),
      );
}

/// A tool call returned by the model in a response/delta.
class ToolCall {
  const ToolCall({
    required this.id,
    required this.function,
    this.type = 'function',
    this.index,
  });

  final String id;
  final String type;
  final ToolCallFunction function;

  /// Present in streaming deltas to identify parallel tool calls.
  final int? index;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'function': function.toJson(),
        if (index != null) 'index': index,
      };

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? 'function').toString(),
        function:
            ToolCallFunction.fromJson(json['function'] as Map<String, dynamic>),
        index: json['index'] is int ? json['index'] as int : null,
      );
}

/// Controls which tool the model may call. Serializes to either a bare string
/// (`'auto'`, `'none'`, `'required'`) or a function-forcing object.
class ToolChoice {
  const ToolChoice._(this._value);

  final Object _value;

  static const ToolChoice auto = ToolChoice._('auto');
  static const ToolChoice none = ToolChoice._('none');
  static const ToolChoice required = ToolChoice._('required');

  /// Force the model to call the named function.
  factory ToolChoice.function(String name) => ToolChoice._(<String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{'name': name},
      });

  /// The JSON value (String or Map) to embed under `tool_choice`.
  Object toJson() => _value;
}
```

- [ ] **Step 2: Export it**

Append to `packages/insforge_ai/lib/insforge_ai.dart`:

```dart
export 'src/models/tool.dart';
```

- [ ] **Step 3: Analyze**

Run: `cd packages/insforge_ai && dart analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add packages/insforge_ai/lib/src/models/tool.dart packages/insforge_ai/lib/insforge_ai.dart
git commit -m "feat(ai): add Tool/ToolCall/ToolChoice models"
```

---

## Task 5: `ChatMessage` + convenience constructors

**Files:**
- Create: `packages/insforge_ai/lib/src/models/chat_message.dart`
- Test: `packages/insforge_ai/test/chat_message_test.dart`
- Modify: `packages/insforge_ai/lib/insforge_ai.dart`

`ChatMessage.content` is a union of `String` (the common case) or `List<ContentPart>` (multimodal). It serializes to a JSON string or an array accordingly.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_ai/test/chat_message_test.dart
import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

void main() {
  group('ChatMessage convenience constructors', () {
    test('user/.assistant/.system set role and string content', () {
      expect(ChatMessage.user('hi').role, 'user');
      expect(ChatMessage.user('hi').content, 'hi');
      expect(ChatMessage.assistant('yo').role, 'assistant');
      expect(ChatMessage.system('be terse').role, 'system');
    });

    test('a plain string message serializes content as a JSON string', () {
      final json = ChatMessage.user('hello').toJson();
      expect(json['role'], 'user');
      expect(json['content'], 'hello');
    });

    test('userWithImages builds a multimodal content array', () {
      final msg = ChatMessage.userWithImages(
        'What is in these images?',
        <String>['https://x.com/a.jpg', 'data:image/png;base64,AAAA'],
      );
      final json = msg.toJson();
      expect(json['role'], 'user');

      final content = json['content'] as List<dynamic>;
      expect(content, hasLength(3));

      expect(content[0], <String, dynamic>{
        'type': 'text',
        'text': 'What is in these images?',
      });
      expect(content[1], <String, dynamic>{
        'type': 'image_url',
        'image_url': <String, dynamic>{'url': 'https://x.com/a.jpg'},
      });
      expect(content[2], <String, dynamic>{
        'type': 'image_url',
        'image_url': <String, dynamic>{'url': 'data:image/png;base64,AAAA'},
      });
    });

    test('serializes tool_call_id under snake_case for tool messages', () {
      final msg = ChatMessage.tool(toolCallId: 'call_1', content: '42');
      final json = msg.toJson();
      expect(json['role'], 'tool');
      expect(json['content'], '42');
      expect(json['tool_call_id'], 'call_1');
    });

    test('parses a response message with tool_calls', () {
      final msg = ChatMessage.fromJson(<String, dynamic>{
        'role': 'assistant',
        'content': null,
        'tool_calls': <dynamic>[
          <String, dynamic>{
            'id': 'call_1',
            'type': 'function',
            'function': <String, dynamic>{
              'name': 'get_weather',
              'arguments': '{"city":"SF"}',
            },
          },
        ],
      });
      expect(msg.role, 'assistant');
      expect(msg.toolCalls, hasLength(1));
      expect(msg.toolCalls!.single.function.name, 'get_weather');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/chat_message_test.dart`
Expected: FAIL — `ChatMessage` is not defined.

- [ ] **Step 3: Write `chat_message.dart`**

```dart
// packages/insforge_ai/lib/src/models/chat_message.dart
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
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_ai/lib/insforge_ai.dart`:

```dart
export 'src/models/chat_message.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_ai && dart test test/chat_message_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_ai/lib/src/models/chat_message.dart packages/insforge_ai/lib/insforge_ai.dart packages/insforge_ai/test/chat_message_test.dart
git commit -m "feat(ai): add ChatMessage with convenience constructors"
```

---

## Task 6: `Usage` + `ChatCompletionRequest` (snake_case serialization)

**Files:**
- Create: `packages/insforge_ai/lib/src/models/usage.dart`
- Create: `packages/insforge_ai/lib/src/models/chat_completion.dart` (request half)
- Test: `packages/insforge_ai/test/chat_completion_request_test.dart`
- Modify: `packages/insforge_ai/lib/insforge_ai.dart`

This task adds `Usage` and the request type with strict OpenAI snake_case (`max_tokens`, `top_p`, `tool_choice`). The response half lands in Task 7.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_ai/test/chat_completion_request_test.dart
import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

void main() {
  group('ChatCompletionRequest.toJson', () {
    test('serializes optional fields to snake_case and defaults stream=false',
        () {
      final req = ChatCompletionRequest(
        model: 'openai/gpt-4o',
        messages: <ChatMessage>[ChatMessage.user('hello')],
        temperature: 0.7,
        maxTokens: 256,
        topP: 0.9,
      );
      final json = req.toJson();

      expect(json['model'], 'openai/gpt-4o');
      expect(json['temperature'], 0.7);
      expect(json['max_tokens'], 256);
      expect(json['top_p'], 0.9);
      expect(json['stream'], false);
      expect((json['messages'] as List<dynamic>).single,
          <String, dynamic>{'role': 'user', 'content': 'hello'});
    });

    test('omits null optionals', () {
      final req = ChatCompletionRequest(
        model: 'm',
        messages: <ChatMessage>[ChatMessage.user('x')],
      );
      final json = req.toJson();
      expect(json.containsKey('temperature'), isFalse);
      expect(json.containsKey('max_tokens'), isFalse);
      expect(json.containsKey('top_p'), isFalse);
      expect(json.containsKey('tools'), isFalse);
      expect(json.containsKey('tool_choice'), isFalse);
    });

    test('serializes tools and tool_choice', () {
      final req = ChatCompletionRequest(
        model: 'm',
        messages: <ChatMessage>[ChatMessage.user('x')],
        tools: <Tool>[
          Tool(
            function: ToolFunction(
              name: 'get_weather',
              parameters: <String, dynamic>{'type': 'object'},
            ),
          ),
        ],
        toolChoice: ToolChoice.function('get_weather'),
      );
      final json = req.toJson();

      final tools = json['tools'] as List<dynamic>;
      expect((tools.single as Map<String, dynamic>)['type'], 'function');

      expect(json['tool_choice'], <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{'name': 'get_weather'},
      });
    });

    test('serializes a bare-string tool_choice', () {
      final req = ChatCompletionRequest(
        model: 'm',
        messages: <ChatMessage>[ChatMessage.user('x')],
        toolChoice: ToolChoice.auto,
      );
      expect(req.toJson()['tool_choice'], 'auto');
    });
  });

  group('Usage.fromJson', () {
    test('parses token counts', () {
      final usage = Usage.fromJson(<String, dynamic>{
        'prompt_tokens': 10,
        'completion_tokens': 20,
        'total_tokens': 30,
      });
      expect(usage.promptTokens, 10);
      expect(usage.completionTokens, 20);
      expect(usage.totalTokens, 30);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/chat_completion_request_test.dart`
Expected: FAIL — `ChatCompletionRequest`/`Usage` not defined.

- [ ] **Step 3: Write `usage.dart`**

```dart
// packages/insforge_ai/lib/src/models/usage.dart

/// Token usage reported by the model.
class Usage {
  const Usage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  factory Usage.fromJson(Map<String, dynamic> json) => Usage(
        promptTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (json['completion_tokens'] as num?)?.toInt() ?? 0,
        totalTokens: (json['total_tokens'] as num?)?.toInt() ?? 0,
      );
}
```

- [ ] **Step 4: Write `chat_completion.dart` (request half only for now)**

```dart
// packages/insforge_ai/lib/src/models/chat_completion.dart
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
```

(The response types — `ChatCompletionResponse`, `Choice`, `ResponseMessage` — are appended to this same file in Task 7.)

- [ ] **Step 5: Export them**

Append to `packages/insforge_ai/lib/insforge_ai.dart`:

```dart
export 'src/models/usage.dart';
export 'src/models/chat_completion.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/insforge_ai && dart test test/chat_completion_request_test.dart`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/insforge_ai/lib/src/models/usage.dart packages/insforge_ai/lib/src/models/chat_completion.dart packages/insforge_ai/lib/insforge_ai.dart packages/insforge_ai/test/chat_completion_request_test.dart
git commit -m "feat(ai): add Usage and ChatCompletionRequest (snake_case)"
```

---

## Task 7: `ChatCompletionResponse` + `Choice` + `ResponseMessage`

**Files:**
- Modify: `packages/insforge_ai/lib/src/models/chat_completion.dart` (append response types)
- Test: `packages/insforge_ai/test/chat_completion_response_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_ai/test/chat_completion_response_test.dart
import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

void main() {
  group('ChatCompletionResponse.fromJson', () {
    test('parses id, model, choices, and usage', () {
      final resp = ChatCompletionResponse.fromJson(<String, dynamic>{
        'id': 'chatcmpl-1',
        'model': 'openai/gpt-4o',
        'choices': <dynamic>[
          <String, dynamic>{
            'index': 0,
            'message': <String, dynamic>{
              'role': 'assistant',
              'content': 'Hello there.',
            },
            'finish_reason': 'stop',
          },
        ],
        'usage': <String, dynamic>{
          'prompt_tokens': 5,
          'completion_tokens': 7,
          'total_tokens': 12,
        },
      });

      expect(resp.id, 'chatcmpl-1');
      expect(resp.model, 'openai/gpt-4o');
      expect(resp.choices, hasLength(1));

      final choice = resp.choices.single;
      expect(choice.index, 0);
      expect(choice.finishReason, 'stop');
      expect(choice.message.role, 'assistant');
      expect(choice.message.content, 'Hello there.');

      expect(resp.usage?.totalTokens, 12);

      // Convenience accessor for the first choice's text.
      expect(resp.content, 'Hello there.');
    });

    test('parses tool_calls in the response message', () {
      final resp = ChatCompletionResponse.fromJson(<String, dynamic>{
        'id': 'chatcmpl-2',
        'model': 'm',
        'choices': <dynamic>[
          <String, dynamic>{
            'index': 0,
            'message': <String, dynamic>{
              'role': 'assistant',
              'content': null,
              'tool_calls': <dynamic>[
                <String, dynamic>{
                  'id': 'call_1',
                  'type': 'function',
                  'function': <String, dynamic>{
                    'name': 'get_weather',
                    'arguments': '{"city":"SF"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });

      final choice = resp.choices.single;
      expect(choice.finishReason, 'tool_calls');
      expect(choice.message.toolCalls, hasLength(1));
      expect(choice.message.toolCalls!.single.function.name, 'get_weather');
      expect(resp.usage, isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/chat_completion_response_test.dart`
Expected: FAIL — `ChatCompletionResponse` not defined.

- [ ] **Step 3: Append the response types to `chat_completion.dart`**

Add the following to the end of `packages/insforge_ai/lib/src/models/chat_completion.dart`:

```dart
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
  String? get content =>
      choices.isEmpty ? null : choices.first.message.content;

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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_ai && dart test test/chat_completion_response_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_ai/lib/src/models/chat_completion.dart packages/insforge_ai/test/chat_completion_response_test.dart
git commit -m "feat(ai): add ChatCompletionResponse/Choice/ResponseMessage"
```

---

## Task 8: Streaming models (`ChatCompletionChunk`, `ChunkChoice`, `Delta`)

**Files:**
- Create: `packages/insforge_ai/lib/src/models/chat_chunk.dart`
- Modify: `packages/insforge_ai/lib/insforge_ai.dart`

Exercised by the streaming test in Task 12. A small standalone test locks the parsing shape now.

- [ ] **Step 1: Write the failing test**

Append to a new test file:

```dart
// packages/insforge_ai/test/chat_chunk_test.dart
import 'package:insforge_ai/insforge_ai.dart';
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/chat_chunk_test.dart`
Expected: FAIL — `ChatCompletionChunk` not defined.

- [ ] **Step 3: Write `chat_chunk.dart`**

```dart
// packages/insforge_ai/lib/src/models/chat_chunk.dart
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
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_ai/lib/insforge_ai.dart`:

```dart
export 'src/models/chat_chunk.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_ai && dart test test/chat_chunk_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_ai/lib/src/models/chat_chunk.dart packages/insforge_ai/lib/insforge_ai.dart packages/insforge_ai/test/chat_chunk_test.dart
git commit -m "feat(ai): add streaming chunk models"
```

---

## Task 9: Images, Embeddings, and AiModel models

**Files:**
- Create: `packages/insforge_ai/lib/src/models/images.dart`
- Create: `packages/insforge_ai/lib/src/models/embeddings.dart`
- Create: `packages/insforge_ai/lib/src/models/ai_model.dart`
- Modify: `packages/insforge_ai/lib/insforge_ai.dart`

These are exercised by the API tests in Tasks 13-15. No dedicated model test here.

- [ ] **Step 1: Write `images.dart`**

OpenRouter performs image generation through `/chat/completions` with `modalities: ['image','text']`; generated images are returned as base64 data URLs in `message.images[].image_url.url`. We keep the **public surface** OpenAI-compatible (`ImageGenerationResponse{created, data[]}` with `url`/`b64Json`), and the [Images] API (Task 14) adapts the chat response into it.

```dart
// packages/insforge_ai/lib/src/models/images.dart

/// An OpenAI-compatible image generation request.
///
/// On OpenRouter this is fulfilled via `/chat/completions` with
/// `modalities: ['image','text']`; the [Images] API performs that mapping.
class ImageGenerationRequest {
  const ImageGenerationRequest({
    required this.model,
    required this.prompt,
    this.n,
    this.size,
  });

  final String model;
  final String prompt;
  final int? n;
  final String? size;
}

/// One generated image. OpenRouter returns base64 data URLs; we expose both a
/// raw [url] (which may be a `data:` URI) and the decoded base64 payload
/// [b64Json] (the part after `base64,`) when present.
class GeneratedImage {
  const GeneratedImage({this.url, this.b64Json});

  final String? url;
  final String? b64Json;

  /// Builds a [GeneratedImage] from an `image_url.url` value, splitting out the
  /// base64 payload from a `data:` URI when present.
  factory GeneratedImage.fromImageUrl(String url) {
    final marker = url.indexOf('base64,');
    if (url.startsWith('data:') && marker != -1) {
      return GeneratedImage(
        url: url,
        b64Json: url.substring(marker + 'base64,'.length),
      );
    }
    return GeneratedImage(url: url);
  }
}

/// An OpenAI-compatible image generation response.
class ImageGenerationResponse {
  const ImageGenerationResponse({required this.created, required this.data});

  final int created;
  final List<GeneratedImage> data;
}
```

- [ ] **Step 2: Write `embeddings.dart`**

```dart
// packages/insforge_ai/lib/src/models/embeddings.dart
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
```

- [ ] **Step 3: Write `ai_model.dart`**

```dart
// packages/insforge_ai/lib/src/models/ai_model.dart

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
```

- [ ] **Step 4: Export them**

Append to `packages/insforge_ai/lib/insforge_ai.dart`:

```dart
export 'src/models/images.dart';
export 'src/models/embeddings.dart';
export 'src/models/ai_model.dart';
```

- [ ] **Step 5: Analyze**

Run: `cd packages/insforge_ai && dart analyze`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_ai/lib/src/models/images.dart packages/insforge_ai/lib/src/models/embeddings.dart packages/insforge_ai/lib/src/models/ai_model.dart packages/insforge_ai/lib/insforge_ai.dart
git commit -m "feat(ai): add images/embeddings/model value types"
```

---

## Task 10: Test support adapters

**Files:**
- Create: `packages/insforge_ai/test/support/recording_adapter.dart`
- Create: `packages/insforge_ai/test/support/sse_adapter.dart`

These are shared test doubles. The recording adapter captures the request body so later tests can assert snake_case fields; the SSE adapter streams `data:` lines for the streaming test. No commit-only build — they land alongside the tests that use them, but we create them here so subsequent tasks compile.

- [ ] **Step 1: Write `recording_adapter.dart`**

```dart
// packages/insforge_ai/test/support/recording_adapter.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Records each request's decoded JSON body + headers and returns a canned
/// JSON response with a fixed status code.
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.responseBody, {this.statusCode = 200});

  final String responseBody;
  final int statusCode;

  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];
  final List<Map<String, List<String>>> headers =
      <Map<String, List<String>>>[];
  final List<String> paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    headers.add(options.headers.map(
      (k, v) => MapEntry(k, <String>[v.toString()]),
    ));

    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = chunks.expand((c) => c).toList();
      final text = utf8.decode(bytes);
      if (text.isNotEmpty) {
        bodies.add(jsonDecode(text) as Map<String, dynamic>);
      }
    }

    return ResponseBody.fromString(
      responseBody,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: Write `sse_adapter.dart`**

```dart
// packages/insforge_ai/test/support/sse_adapter.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Returns a streamed response whose body yields the supplied SSE [lines]
/// (each already a full `data: {...}` payload) terminated by `data: [DONE]`.
///
/// Lines are emitted across multiple chunks (with a split mid-line) to prove
/// the parser correctly buffers partial SSE frames.
class SseAdapter implements HttpClientAdapter {
  SseAdapter(this.dataPayloads);

  /// Each entry is the JSON string after `data: ` (without the prefix).
  final List<String> dataPayloads;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final buffer = StringBuffer();
    for (final payload in dataPayloads) {
      buffer.write('data: $payload\n\n');
    }
    buffer.write('data: [DONE]\n\n');
    final full = buffer.toString();

    // Split the byte stream at an awkward offset to exercise buffering.
    final bytes = utf8.encode(full);
    final mid = bytes.length ~/ 2;
    final stream = Stream<Uint8List>.fromIterable(<Uint8List>[
      Uint8List.fromList(bytes.sublist(0, mid)),
      Uint8List.fromList(bytes.sublist(mid)),
    ]);

    return ResponseBody(
      stream,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 3: Analyze**

Run: `cd packages/insforge_ai && dart analyze`
Expected: "No issues found!" (unused-import/dead-code lints may appear only once the adapters are referenced by tests in later tasks; that is expected and resolved as those tasks land.)

- [ ] **Step 4: Commit**

```bash
git add packages/insforge_ai/test/support/recording_adapter.dart packages/insforge_ai/test/support/sse_adapter.dart
git commit -m "test(ai): add recording + SSE test adapters"
```

---

## Task 11: `AIClient` construction + headers

**Files:**
- Create: `packages/insforge_ai/lib/src/ai_client.dart`
- Test: `packages/insforge_ai/test/ai_client_test.dart`
- Modify: `packages/insforge_ai/lib/insforge_ai.dart`

`AIClient` owns its own `Dio` (or accepts an injected one). It sets `Authorization: Bearer <apiKey>`, `baseUrl`, and optional `HTTP-Referer`/`X-Title`. The sub-namespaces (`chat.completions`, `images`, `embeddings`, `models`) are wired here; their implementations land in Tasks 12-15. To keep this task green, we wire `chat`/`images`/`embeddings`/`models` after those classes exist, so we declare the namespace fields as `late final` and build the sub-API classes (which are stubbed minimally here and fully implemented next). To avoid forward-reference churn, we implement the sub-API classes in this task with their full bodies referenced from the later tasks' files — therefore this task creates `ai_client.dart` with the namespaces pointing at the API classes created in Tasks 12-15.

**To avoid circular task ordering, implement this task's `ai_client.dart` to construct/configure the Dio and expose the API classes; the API class files themselves are created in Tasks 12-15. This task's test only asserts construction + headers and uses the [RecordingAdapter] against a raw `chat.completions.create` call, so Task 12 must be completed in tandem. Recommended: do Tasks 11 and 12 together (they share `chat_completions.dart` and `ai_client.dart`).**

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_ai/test/ai_client_test.dart
import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

void main() {
  group('AIClient construction', () {
    test('defaults the base URL to OpenRouter', () {
      final client = AIClient('sk-or-test');
      expect(client.dio.options.baseUrl, 'https://openrouter.ai/api/v1');
    });

    test('sets the Authorization bearer header', () {
      final client = AIClient('sk-or-test');
      expect(
        client.dio.options.headers['Authorization'],
        'Bearer sk-or-test',
      );
    });

    test('adds HTTP-Referer and X-Title when provided', () {
      final client = AIClient(
        'sk-or-test',
        referer: 'https://myapp.example',
        title: 'My App',
      );
      expect(client.dio.options.headers['HTTP-Referer'],
          'https://myapp.example');
      expect(client.dio.options.headers['X-Title'], 'My App');
    });

    test('omits ranking headers when not provided', () {
      final client = AIClient('sk-or-test');
      expect(client.dio.options.headers.containsKey('HTTP-Referer'), isFalse);
      expect(client.dio.options.headers.containsKey('X-Title'), isFalse);
    });

    test('uses an injected Dio', () {
      final dio = Dio();
      final client = AIClient('sk-or-test', dio: dio);
      expect(identical(client.dio, dio), isTrue);
      // Injected Dio is still configured with base URL + auth.
      expect(client.dio.options.baseUrl, 'https://openrouter.ai/api/v1');
      expect(client.dio.options.headers['Authorization'], 'Bearer sk-or-test');
    });

    test('sends the bearer header on a request (via injected adapter)',
        () async {
      final dio = Dio();
      final adapter = RecordingAdapter('{"id":"x","model":"m","choices":[]}');
      dio.httpClientAdapter = adapter;
      final client = AIClient('sk-or-test', dio: dio);

      await client.chat.completions.create(
        ChatCompletionRequest(
          model: 'm',
          messages: <ChatMessage>[ChatMessage.user('hi')],
        ),
      );

      expect(adapter.headers.single['Authorization'],
          <String>['Bearer sk-or-test']);
      expect(adapter.paths.single, '/chat/completions');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/ai_client_test.dart`
Expected: FAIL — `AIClient` not defined. (Complete this together with Task 12.)

- [ ] **Step 3: Write `ai_client.dart`**

```dart
// packages/insforge_ai/lib/src/ai_client.dart
import 'package:dio/dio.dart';

import 'chat_completions.dart';
import 'embeddings_api.dart';
import 'images_api.dart';
import 'models_api.dart';

/// Default OpenRouter API base URL.
const String openRouterBaseUrl = 'https://openrouter.ai/api/v1';

const String _userAgent = 'insforge-flutter-ai/0.1.0';

/// Groups the chat sub-namespace (`client.chat.completions`).
class Chat {
  Chat(Dio dio) : completions = ChatCompletions(dio);

  final ChatCompletions completions;
}

/// A standalone OpenRouter (OpenAI-compatible) AI client.
///
/// Owns its own [Dio] pointed at OpenRouter (or an injected one for tests),
/// with `Authorization: Bearer <apiKey>` and optional ranking headers.
/// Has no InsForge backend coupling beyond shared error types.
class AIClient {
  AIClient(
    String apiKey, {
    String baseUrl = openRouterBaseUrl,
    Dio? dio,
    String? referer,
    String? title,
  }) : dio = dio ?? Dio() {
    this.dio.options
      ..baseUrl = baseUrl
      ..headers = <String, dynamic>{
        'Authorization': 'Bearer $apiKey',
        'User-Agent': _userAgent,
        if (referer != null) 'HTTP-Referer': referer,
        if (title != null) 'X-Title': title,
        ...this.dio.options.headers,
      }
      ..validateStatus =
          (int? status) => status != null && status >= 200 && status < 300;

    chat = Chat(this.dio);
    images = Images(this.dio);
    embeddings = Embeddings(this.dio);
    models = Models(this.dio);
  }

  final Dio dio;

  /// `client.chat.completions.create(...)` / `.createStream(...)`.
  late final Chat chat;

  /// `client.images.generate(...)`.
  late final Images images;

  /// `client.embeddings.create(...)`.
  late final Embeddings embeddings;

  /// `client.models.list()`.
  late final Models models;
}
```

> **Note on the header merge:** spreading `...this.dio.options.headers` last preserves any headers already present on an injected Dio while still applying the auth/ranking headers. Because `headers` is reassigned to a fresh map, the auth headers take precedence only if not already set by the caller; if a test needs to assert the exact value, construct the client with a bare `Dio()` (as the tests do).

- [ ] **Step 4: Export it**

Append to `packages/insforge_ai/lib/insforge_ai.dart`:

```dart
export 'src/ai_client.dart';
```

- [ ] **Step 5: Run the test (after Task 12 lands `chat_completions.dart`)**

Run: `cd packages/insforge_ai && dart test test/ai_client_test.dart`
Expected: All tests PASS (requires `ChatCompletions`, `Images`, `Embeddings`, `Models` to exist — implement Tasks 12-15; the construction-only sub-tests pass once those classes compile).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_ai/lib/src/ai_client.dart packages/insforge_ai/lib/insforge_ai.dart packages/insforge_ai/test/ai_client_test.dart
git commit -m "feat(ai): add AIClient with OpenRouter Dio + ranking headers"
```

---

## Task 12: `ChatCompletions.create` + `createStream`

**Files:**
- Create: `packages/insforge_ai/lib/src/chat_completions.dart`
- Test: `packages/insforge_ai/test/chat_completions_create_test.dart`
- Test: `packages/insforge_ai/test/chat_completions_stream_test.dart`

`create` POSTs `/chat/completions` and parses the response. `createStream` POSTs with `stream: true` and `ResponseType.stream`, parses SSE `data:` frames, skips `[DONE]`, and yields `ChatCompletionChunk`s via `async*`.

- [ ] **Step 1: Write the failing `create` test**

```dart
// packages/insforge_ai/test/chat_completions_create_test.dart
import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

import 'support/recording_adapter.dart';

void main() {
  group('ChatCompletions.create', () {
    test('POSTs snake_case body to /chat/completions and parses the response',
        () async {
      final dio = Dio();
      final adapter = RecordingAdapter(
        '{"id":"chatcmpl-1","model":"openai/gpt-4o",'
        '"choices":[{"index":0,"message":{"role":"assistant",'
        '"content":"Hi!"},"finish_reason":"stop"}],'
        '"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}',
      );
      dio.httpClientAdapter = adapter;
      final client = AIClient('sk-or-test', dio: dio);

      final resp = await client.chat.completions.create(
        ChatCompletionRequest(
          model: 'openai/gpt-4o',
          messages: <ChatMessage>[ChatMessage.user('hi')],
          maxTokens: 64,
          topP: 0.8,
        ),
      );

      // Request body is snake_case + stream:false.
      final body = adapter.bodies.single;
      expect(adapter.paths.single, '/chat/completions');
      expect(body['model'], 'openai/gpt-4o');
      expect(body['max_tokens'], 64);
      expect(body['top_p'], 0.8);
      expect(body['stream'], false);

      // Response parsed.
      expect(resp.id, 'chatcmpl-1');
      expect(resp.content, 'Hi!');
      expect(resp.choices.single.finishReason, 'stop');
      expect(resp.usage?.totalTokens, 5);
    });

    test('throws InsforgeHttpException with nested OpenRouter error', () async {
      final dio = Dio();
      dio.httpClientAdapter = RecordingAdapter(
        '{"error":{"message":"model is required","code":"invalid_request"}}',
        statusCode: 400,
      );
      final client = AIClient('sk-or-test', dio: dio);

      expect(
        () => client.chat.completions.create(
          ChatCompletionRequest(
            model: '',
            messages: <ChatMessage>[ChatMessage.user('hi')],
          ),
        ),
        throwsA(
          isA<InsforgeHttpException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', 'model is required')
              .having((e) => e.error, 'error', 'invalid_request'),
        ),
      );
    });
  });
}
```

- [ ] **Step 2: Write the failing `createStream` test**

```dart
// packages/insforge_ai/test/chat_completions_stream_test.dart
import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
import 'package:test/test.dart';

import 'support/sse_adapter.dart';

void main() {
  group('ChatCompletions.createStream', () {
    test('parses SSE chunks into content deltas and stops at [DONE]',
        () async {
      final dio = Dio();
      dio.httpClientAdapter = SseAdapter(<String>[
        '{"id":"c","model":"m","choices":[{"index":0,'
            '"delta":{"content":"Hel"},"finish_reason":null}]}',
        '{"id":"c","model":"m","choices":[{"index":0,'
            '"delta":{"content":"lo"},"finish_reason":null}]}',
        '{"id":"c","model":"m","choices":[{"index":0,'
            '"delta":{},"finish_reason":"stop"}]}',
      ]);
      final client = AIClient('sk-or-test', dio: dio);

      final chunks = await client.chat.completions
          .createStream(
            ChatCompletionRequest(
              model: 'm',
              messages: <ChatMessage>[ChatMessage.user('hi')],
            ),
          )
          .toList();

      // Three data frames before [DONE].
      expect(chunks, hasLength(3));
      final text = chunks
          .map((c) => c.contentDelta ?? '')
          .join();
      expect(text, 'Hello');
      expect(chunks.last.choices.single.finishReason, 'stop');
    });

    test('ignores blank lines and non-data lines', () async {
      final dio = Dio();
      // The SSE adapter already wraps payloads with blank-line separators; a
      // payload that is a comment-like ping should be skipped by the parser if
      // it does not start with `data: `. Here we only feed valid frames and a
      // trailing [DONE]; assert we get exactly the valid frames.
      dio.httpClientAdapter = SseAdapter(<String>[
        '{"choices":[{"index":0,"delta":{"content":"A"}}]}',
      ]);
      final client = AIClient('sk-or-test', dio: dio);

      final chunks = await client.chat.completions
          .createStream(
            ChatCompletionRequest(
              model: 'm',
              messages: <ChatMessage>[ChatMessage.user('hi')],
            ),
          )
          .toList();

      expect(chunks, hasLength(1));
      expect(chunks.single.contentDelta, 'A');
    });
  });
}
```

- [ ] **Step 3: Run them to verify they fail**

Run: `cd packages/insforge_ai && dart test test/chat_completions_create_test.dart test/chat_completions_stream_test.dart`
Expected: FAIL — `ChatCompletions` not defined.

- [ ] **Step 4: Write `chat_completions.dart`**

```dart
// packages/insforge_ai/lib/src/chat_completions.dart
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'errors.dart';
import 'models/chat_chunk.dart';
import 'models/chat_completion.dart';

/// The `chat.completions` sub-namespace.
class ChatCompletions {
  ChatCompletions(this._dio);

  final Dio _dio;

  /// Creates a non-streaming chat completion (`POST /chat/completions`).
  Future<ChatCompletionResponse> create(ChatCompletionRequest request) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/completions',
        data: request.toJson(streamOverride: false),
      );
      return ChatCompletionResponse.fromJson(response.data ?? <String, dynamic>{});
    } on DioException catch (e) {
      throw mapOpenRouterError(e);
    }
  }

  /// Creates a streaming chat completion, yielding chunks as they arrive
  /// (`POST /chat/completions` with `stream: true`).
  Stream<ChatCompletionChunk> createStream(
    ChatCompletionRequest request,
  ) async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/chat/completions',
        data: request.toJson(streamOverride: true),
        options: Options(responseType: ResponseType.stream),
      );
    } on DioException catch (e) {
      throw mapOpenRouterError(e);
    }

    final body = response.data;
    if (body == null) return;

    // Decode the byte stream to text and split into lines, buffering partial
    // SSE frames across chunk boundaries.
    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;

      final data = trimmed.substring('data:'.length).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') return;

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } on FormatException {
        // Skip malformed frames rather than aborting the stream.
        continue;
      }
      yield ChatCompletionChunk.fromJson(json);
    }
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd packages/insforge_ai && dart test test/chat_completions_create_test.dart test/chat_completions_stream_test.dart`
Expected: All tests PASS.

Also re-run the Task 11 client test now that `ChatCompletions` exists:
Run: `cd packages/insforge_ai && dart test test/ai_client_test.dart`
Expected: All tests PASS (once Tasks 13-15 land the other API classes; if running before those, temporarily expect the `Images`/`Embeddings`/`Models` references to be unresolved — implement them next).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_ai/lib/src/chat_completions.dart packages/insforge_ai/test/chat_completions_create_test.dart packages/insforge_ai/test/chat_completions_stream_test.dart
git commit -m "feat(ai): add ChatCompletions create + SSE createStream"
```

---

## Task 13: `Images.generate` (via /chat/completions with modalities)

**Files:**
- Create: `packages/insforge_ai/lib/src/images_api.dart`
- Test: `packages/insforge_ai/test/images_test.dart`

**Design decision (documented):** OpenRouter does **not** expose a dedicated `/images/generations` endpoint for most models; image generation is performed via `/chat/completions` with `modalities: ['image','text']`, and generated images are returned as base64 data URLs in `choices[0].message.images[].image_url.url` (confirmed via context7 against the OpenRouter docs). We therefore implement `Images.generate` by building a chat request from the [ImageGenerationRequest] prompt and adapting the chat response into the OpenAI-compatible [ImageGenerationResponse] (`data[]` with `url` + `b64Json`). This keeps the public surface OpenAI-shaped while matching OpenRouter's real transport.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_ai/test/images_test.dart
import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
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
      expect((messages.single as Map<String, dynamic>)['content'],
          'a sunset over mountains');

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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/images_test.dart`
Expected: FAIL — `Images` not defined.

- [ ] **Step 3: Write `images_api.dart`**

```dart
// packages/insforge_ai/lib/src/images_api.dart
import 'package:dio/dio.dart';

import 'errors.dart';
import 'models/images.dart';

/// The `images` sub-namespace.
///
/// OpenRouter generates images through `/chat/completions` with
/// `modalities: ['image','text']`; this class adapts that into the
/// OpenAI-compatible [ImageGenerationResponse].
class Images {
  Images(this._dio);

  final Dio _dio;

  /// Generates one or more images for [request].prompt.
  Future<ImageGenerationResponse> generate(
    ImageGenerationRequest request,
  ) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/chat/completions',
        data: <String, dynamic>{
          'model': request.model,
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{'role': 'user', 'content': request.prompt},
          ],
          'modalities': <String>['image', 'text'],
        },
      );
    } on DioException catch (e) {
      throw mapOpenRouterError(e);
    }

    final data = response.data ?? <String, dynamic>{};
    final images = <GeneratedImage>[];

    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      final message = first is Map<String, dynamic> ? first['message'] : null;
      final rawImages =
          message is Map<String, dynamic> ? message['images'] : null;
      if (rawImages is List) {
        for (final img in rawImages.whereType<Map<String, dynamic>>()) {
          final imageUrl = img['image_url'];
          final url =
              imageUrl is Map<String, dynamic> ? imageUrl['url'] : null;
          if (url is String && url.isNotEmpty) {
            images.add(GeneratedImage.fromImageUrl(url));
          }
        }
      }
    }

    return ImageGenerationResponse(
      created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      data: images,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_ai && dart test test/images_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_ai/lib/src/images_api.dart packages/insforge_ai/test/images_test.dart
git commit -m "feat(ai): add Images.generate via chat modalities"
```

---

## Task 14: `Embeddings.create`

**Files:**
- Create: `packages/insforge_ai/lib/src/embeddings_api.dart`
- Test: `packages/insforge_ai/test/embeddings_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_ai/test/embeddings_test.dart
import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/embeddings_test.dart`
Expected: FAIL — `Embeddings` not defined.

- [ ] **Step 3: Write `embeddings_api.dart`**

```dart
// packages/insforge_ai/lib/src/embeddings_api.dart
import 'package:dio/dio.dart';

import 'errors.dart';
import 'models/embeddings.dart';

/// The `embeddings` sub-namespace.
class Embeddings {
  Embeddings(this._dio);

  final Dio _dio;

  /// Creates embeddings for [request].input (`POST /embeddings`).
  Future<EmbeddingsResponse> create(EmbeddingsRequest request) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/embeddings',
        data: request.toJson(),
      );
      return EmbeddingsResponse.fromJson(
        response.data ?? <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw mapOpenRouterError(e);
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_ai && dart test test/embeddings_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_ai/lib/src/embeddings_api.dart packages/insforge_ai/test/embeddings_test.dart
git commit -m "feat(ai): add Embeddings.create (single + list input)"
```

---

## Task 15: `Models.list`

**Files:**
- Create: `packages/insforge_ai/lib/src/models_api.dart`
- Test: `packages/insforge_ai/test/models_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_ai/test/models_test.dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_ai && dart test test/models_test.dart`
Expected: FAIL — `Models` not defined.

- [ ] **Step 3: Write `models_api.dart`**

```dart
// packages/insforge_ai/lib/src/models_api.dart
import 'package:dio/dio.dart';

import 'errors.dart';
import 'models/ai_model.dart';

/// The `models` sub-namespace.
class Models {
  Models(this._dio);

  final Dio _dio;

  /// Lists the available models (`GET /models`).
  Future<List<AiModel>> list() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/models');
      final data = response.data?['data'];
      if (data is! List) return <AiModel>[];
      return data
          .whereType<Map<String, dynamic>>()
          .map(AiModel.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapOpenRouterError(e);
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_ai && dart test test/models_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Run the full package suite + analyze**

Run: `cd packages/insforge_ai && dart test && dart analyze`
Expected: all tests PASS; "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_ai/lib/src/models_api.dart packages/insforge_ai/test/models_test.dart
git commit -m "feat(ai): add Models.list"
```

---

## Self-Review Notes

- **Spec coverage (design §4.6):** `AIClient(apiKey, {baseUrl, dio, referer, title})` with own/injected OpenRouter Dio + `Authorization: Bearer` and optional `HTTP-Referer`/`X-Title` (Task 11); `chat.completions.create` (Task 12) and `chat.completions.createStream` SSE streaming (Task 12); `images.generate` (Task 13); `embeddings.create` (Task 14); `models.list` (Task 15). All hand-written `fromJson`/`toJson` (no build_runner): `ContentPart`/`TextPart`/`ImageUrlPart` (Task 3), `Tool`/`ToolFunction`/`ToolCall`/`ToolChoice` (Task 4), `ChatMessage` with `.user`/`.assistant`/`.system`/`.tool`/`.userWithImages` (Task 5), `Usage` + `ChatCompletionRequest` (Task 6), `ChatCompletionResponse`/`Choice`/`ResponseMessage` (Task 7), `ChatCompletionChunk`/`ChunkChoice`/`Delta` (Task 8), `ImageGenerationRequest`/`Response`/`GeneratedImage`, `EmbeddingsRequest`/`Response`/`EmbeddingData`, `AiModel` (Task 9). Local nested-error mapper `mapOpenRouterError` (Task 2). Covered.
- **Required test coverage (from the brief):** snake_case request serialization `max_tokens`/`top_p`/`tool_choice` (Task 6 + Task 12 over the wire); choices/usage parsing (Task 7, Task 12); `createStream` parses SSE chunks into content deltas and stops at `[DONE]` (Task 12, with the [SseAdapter] splitting frames mid-line to prove buffering); embeddings single vs list input + vector parsing (Task 14); `models.list` parsing (Task 15); `userWithImages` multimodal content array (Task 5); nested OpenRouter `{error:{message,code}}` mapping (Task 2 unit + Task 12 over the wire). All covered.
- **Image generation decision:** OpenRouter has no general dedicated `/images/generations` endpoint; per context7 (OpenRouter docs, "Image Generation"), image-capable models are driven through `POST /chat/completions` with `modalities: ['image','text']`, returning base64 data URLs at `choices[0].message.images[].image_url.url`. `Images.generate` therefore builds a chat request from the prompt and adapts the response into the OpenAI-compatible `ImageGenerationResponse{created, data[]}` (each `GeneratedImage` exposes the raw `url` and the split-out `b64Json`). This keeps the public API OpenAI-shaped while matching OpenRouter's true transport. The `n`/`size` fields on `ImageGenerationRequest` are accepted for OpenAI-compatibility but not forwarded (OpenRouter's chat-modalities path uses `image_config.aspect_ratio`; left as a future enhancement to avoid over-fitting).
- **context7 confirmation:** Yes — `resolve-library-id` → `/llmstxt/openrouter_ai_llms-full_txt`, then `query-docs` confirmed base url `https://openrouter.ai/api/v1`, `/chat/completions` request/response + SSE `data: {...}` / `data: [DONE]` format, `/embeddings` (`input` string|array, `encoding_format`, `dimensions`), image generation via chat `modalities`, and the `HTTP-Referer`/`X-Title` ranking headers.
- **Core dependency surface used:** only the shared exception types from `package:insforge_core/insforge_core.dart` — `InsforgeException`, `InsforgeHttpException(statusCode/error/message/... cause)`, `InsforgeNetworkException`. `InsforgeSerializationException` is available if a future parsing-hardening pass wants it. This package deliberately does **not** use `InsforgeHttpClient`, `ErrorResponse.fromJson` (flat-shape only), or any auth/refresh machinery — it is standalone.
- **Task ordering caveat:** Task 11 (`AIClient`) references the four sub-API classes; its file compiles only once Tasks 12-15 land them. Implement Task 11 and Task 12 together (they share `ai_client.dart` + `chat_completions.dart`), then 13-15; run the full suite at the end of Task 15. This is the one place the strict "fail → pass within a single task" cadence is relaxed, and it is called out in Task 11.
- **Type/name stability for Plan 7:** `AIClient`, `openRouterBaseUrl`, `Chat`, `ChatCompletions`, `Images`, `Embeddings`, `Models`, `ChatCompletionRequest/Response`, `ChatCompletionChunk`, `ChatMessage`, `ContentPart`, `EmbeddingsRequest/Response`, `ImageGenerationRequest/Response`, `AiModel`, `mapOpenRouterError` are the public names Plan 7 (umbrella) imports when an `openRouterApiKey` is supplied — keep them stable.
