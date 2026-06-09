// packages/insforge_auth/test/session_test.dart
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

void main() {
  test('Session.fromJson / toJson round-trips with nested user', () {
    final session = Session.fromJson(<String, dynamic>{
      'accessToken': 'jwt-abc',
      'refreshToken': 'refresh-xyz',
      'user': <String, dynamic>{
        'id': 'u-1',
        'email': 'a@b.com',
        'emailVerified': true,
      },
    });

    expect(session.accessToken, 'jwt-abc');
    expect(session.refreshToken, 'refresh-xyz');
    expect(session.user.id, 'u-1');

    final restored = Session.fromJson(session.toJson());
    expect(restored.accessToken, 'jwt-abc');
    expect(restored.refreshToken, 'refresh-xyz');
    expect(restored.user.email, 'a@b.com');
  });

  test('Session tolerates a null refresh token', () {
    final session = Session.fromJson(<String, dynamic>{
      'accessToken': 'jwt-only',
      'user': <String, dynamic>{'id': 'u', 'email': 'e@e.com'},
    });
    expect(session.refreshToken, isNull);
  });
}
