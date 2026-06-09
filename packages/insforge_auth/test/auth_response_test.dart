// packages/insforge_auth/test/auth_response_test.dart
import 'package:insforge_auth/insforge_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthResponse.fromJson', () {
    test('parses user + tokens', () {
      final r = AuthResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u', 'email': 'e@e.com'},
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      });
      expect(r.accessToken, 'access-1');
      expect(r.refreshToken, 'refresh-1');
      expect(r.user.id, 'u');
    });

    test('tolerates a missing refresh token (web-style body)', () {
      final r = AuthResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u2', 'email': 'e2@e.com'},
        'accessToken': 'access-2',
      });
      expect(r.refreshToken, isNull);
    });

    test('toSession produces a Session carrying the same values', () {
      final r = AuthResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u3', 'email': 'e3@e.com'},
        'accessToken': 'access-3',
        'refreshToken': 'refresh-3',
      });
      final session = r.toSession();
      expect(session.accessToken, 'access-3');
      expect(session.refreshToken, 'refresh-3');
      expect(session.user.id, 'u3');
    });
  });
}
