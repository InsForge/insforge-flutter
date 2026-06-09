// packages/insforge_auth/test/pkce_test.dart
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

void main() {
  group('PkceHelper', () {
    test('generateCodeVerifier produces a 43-128 char base64url string', () {
      final verifier = PkceHelper.generateCodeVerifier();
      expect(verifier.length, greaterThanOrEqualTo(43));
      expect(verifier.length, lessThanOrEqualTo(128));
      // base64url alphabet only (no padding, no + or /).
      expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(verifier), isTrue);
    });

    test('generateCodeVerifier returns distinct values', () {
      final a = PkceHelper.generateCodeVerifier();
      final b = PkceHelper.generateCodeVerifier();
      expect(a, isNot(equals(b)));
    });

    test('codeChallenge matches the RFC 7636 Appendix B vector', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final challenge = PkceHelper.codeChallenge(verifier);
      expect(challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('codeChallenge output is base64url without padding', () {
      final challenge =
          PkceHelper.codeChallenge(PkceHelper.generateCodeVerifier());
      expect(challenge.contains('='), isFalse);
      expect(challenge.contains('+'), isFalse);
      expect(challenge.contains('/'), isFalse);
    });
  });
}
