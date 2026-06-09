// packages/insforge_core/lib/src/url.dart
import 'errors.dart';

const List<String> _moduleMarkers = <String>[
  '/api/auth',
  '/api/database',
  '/api/storage',
  '/api/ai',
  '/api/functions',
  '/functions/',
];

/// Normalizes a project base URL: trims whitespace and a trailing slash,
/// adds a scheme when missing, and rejects URLs that already include a module
/// path (callers must pass only the project base, e.g. `https://x.insforge.app`).
String normalizeBaseUrl(String input, {bool useHttps = true}) {
  var url = input.trim();
  if (url.isEmpty) {
    throw InsforgeException('baseUrl must not be empty');
  }
  for (final marker in _moduleMarkers) {
    if (url.contains(marker)) {
      throw InsforgeException(
        'baseUrl must not contain module paths (found "$marker"). '
        'Pass only the project base URL.',
      );
    }
  }
  if (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = '${useHttps ? 'https' : 'http'}://$url';
  }
  return url;
}
