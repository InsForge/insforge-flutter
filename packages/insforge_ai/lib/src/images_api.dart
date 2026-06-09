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
