// packages/insforge_auth/lib/src/jwt.dart
import 'dart:convert';

/// Decodes the `exp` (expiry) claim of a JWT without verifying the signature.
///
/// Returns the expiry as a UTC [DateTime], or null when the token is malformed
/// or carries no numeric `exp` claim. Used only for proactive-refresh timing —
/// never for authorization decisions.
DateTime? decodeJwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payloadJson = utf8.decode(base64Url.decode(normalized));
    final payload = jsonDecode(payloadJson);
    if (payload is! Map<String, dynamic>) return null;
    final exp = payload['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (exp * 1000).toInt(),
      isUtc: true,
    );
  } catch (_) {
    return null;
  }
}
