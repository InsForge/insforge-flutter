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
      return ChatCompletionResponse.fromJson(
        response.data ?? <String, dynamic>{},
      );
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
