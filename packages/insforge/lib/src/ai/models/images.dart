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
