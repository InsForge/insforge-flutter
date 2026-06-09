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
