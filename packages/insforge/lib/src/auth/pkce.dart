// packages/insforge_auth/lib/src/pkce.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636) helper for OAuth 2.0 authorization-code flows.
///
/// The verifier is a cryptographically random base64url string (43-128 chars);
/// the challenge is `BASE64URL(SHA256(ASCII(verifier)))` without padding.
class PkceHelper {
  PkceHelper._();

  static final Random _random = Random.secure();

  /// Generates a random code verifier.
  ///
  /// 32 random bytes base64url-encode to a 43-character string, which is the
  /// RFC-mandated minimum length and within the 43-128 range.
  static String generateCodeVerifier() {
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return _base64UrlNoPad(bytes);
  }

  /// Derives the code challenge from [verifier]:
  /// `BASE64URL(SHA256(ASCII(verifier)))` with padding stripped.
  static String codeChallenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return _base64UrlNoPad(Uint8List.fromList(digest.bytes));
  }

  static String _base64UrlNoPad(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
