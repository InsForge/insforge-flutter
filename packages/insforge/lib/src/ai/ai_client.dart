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
