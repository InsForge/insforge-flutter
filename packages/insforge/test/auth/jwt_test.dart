// packages/insforge_auth/test/jwt_test.dart
import 'dart:convert';

import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

/// Builds an unsigned-but-structurally-valid JWT carrying the given payload.
String _makeJwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'});
  final body = seg(payload);
  return '$header.$body.signature';
}

void main() {
  group('decodeJwtExpiry', () {
    test('reads the exp claim (seconds) as a UTC DateTime', () {
      // 2026-06-08T10:30:00Z = 1781260200 seconds since epoch.
      const expSeconds = 1781260200;
      final token = _makeJwt(<String, dynamic>{'sub': 'u1', 'exp': expSeconds});

      final result = decodeJwtExpiry(token);

      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.millisecondsSinceEpoch, expSeconds * 1000);
    });

    test('returns null when exp is absent', () {
      final token = _makeJwt(<String, dynamic>{'sub': 'u1'});
      expect(decodeJwtExpiry(token), isNull);
    });

    test('returns null for a malformed token', () {
      expect(decodeJwtExpiry('not.a.jwt.at.all'), isNull);
      expect(decodeJwtExpiry('onlyonesegment'), isNull);
      expect(decodeJwtExpiry(''), isNull);
    });
  });
}
