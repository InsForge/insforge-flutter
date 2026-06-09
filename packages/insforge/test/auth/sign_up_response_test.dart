// packages/insforge_auth/test/sign_up_response_test.dart
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

void main() {
  group('SignUpResponse.fromJson', () {
    test('immediate-session signup (verification disabled)', () {
      final r = SignUpResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u', 'email': 'e@e.com'},
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'requireEmailVerification': false,
      });
      expect(r.accessToken, 'access-1');
      expect(r.refreshToken, 'refresh-1');
      expect(r.requireEmailVerification, isFalse);
      expect(r.hasSession, isTrue);
    });

    test('verification-required signup has no tokens and no session', () {
      final r = SignUpResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u2', 'email': 'e2@e.com'},
        'accessToken': null,
        'refreshToken': null,
        'requireEmailVerification': true,
      });
      expect(r.accessToken, isNull);
      expect(r.refreshToken, isNull);
      expect(r.requireEmailVerification, isTrue);
      expect(r.hasSession, isFalse);
    });

    test('requireEmailVerification defaults to false when absent', () {
      final r = SignUpResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u3', 'email': 'e3@e.com'},
        'accessToken': 'a',
      });
      expect(r.requireEmailVerification, isFalse);
      expect(r.hasSession, isTrue);
    });

    test('tolerates a verification-required body with no user object', () {
      // The real backend omits user/accessToken/refreshToken entirely when
      // email verification is enabled; only a status flag is returned.
      final r = SignUpResponse.fromJson(<String, dynamic>{
        'message': 'Verification email sent',
        'requireEmailVerification': true,
      });
      expect(r.user, isNull);
      expect(r.accessToken, isNull);
      expect(r.refreshToken, isNull);
      expect(r.requireEmailVerification, isTrue);
      expect(r.hasSession, isFalse);
      expect(r.toSession(), isNull);
    });
  });
}
