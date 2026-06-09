// packages/insforge_storage/lib/src/mime.dart

/// Default content type used when an extension is unknown or absent.
const String defaultContentType = 'application/octet-stream';

/// Extension (lowercase, no dot) → MIME type. Mirrors the Kotlin SDK's map,
/// scoped to the types the Flutter SDK design enumerates.
const Map<String, String> _extensionToMime = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'pdf': 'application/pdf',
  'json': 'application/json',
  'txt': 'text/plain',
  'mp4': 'video/mp4',
};

/// Infers a MIME type from [filename]'s extension, falling back to
/// [defaultContentType] (`application/octet-stream`).
///
/// Uses the last path segment and the substring after its final `.`, matched
/// case-insensitively. Returns the fallback when there is no extension.
String contentTypeForFilename(String filename) {
  final lastSlash = filename.lastIndexOf('/');
  final segment =
      lastSlash >= 0 ? filename.substring(lastSlash + 1) : filename;
  final dot = segment.lastIndexOf('.');
  if (dot < 0 || dot == segment.length - 1) {
    return defaultContentType;
  }
  final ext = segment.substring(dot + 1).toLowerCase();
  return _extensionToMime[ext] ?? defaultContentType;
}
