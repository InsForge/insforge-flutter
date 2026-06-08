// packages/insforge_auth/test/user_test.dart
import 'package:insforge_auth/insforge_auth.dart';
import 'package:test/test.dart';

void main() {
  group('User.fromJson', () {
    test('parses a full user with profile name/avatar', () {
      final user = User.fromJson(<String, dynamic>{
        'id': 'u-123',
        'email': 'a@b.com',
        'emailVerified': true,
        'providers': <dynamic>['email', 'google'],
        'profile': <String, dynamic>{
          'name': 'Ada',
          'avatar_url': 'https://img/a.png',
          'bio': 'hi',
        },
        'metadata': <String, dynamic>{'ip': '1.2.3.4'},
        'createdAt': '2026-06-08T10:30:00.000Z',
        'updatedAt': '2026-06-08T11:00:00.000Z',
      });

      expect(user.id, 'u-123');
      expect(user.email, 'a@b.com');
      expect(user.emailVerified, isTrue);
      expect(user.providers, <String>['email', 'google']);
      expect(user.profile?['bio'], 'hi');
      expect(user.metadata?['ip'], '1.2.3.4');
      expect(user.name, 'Ada');
      expect(user.avatarUrl, 'https://img/a.png');
      expect(user.createdAt?.year, 2026);
      expect(user.updatedAt?.minute, 0);
    });

    test('tolerates missing optional fields', () {
      final user = User.fromJson(<String, dynamic>{
        'id': 'u-1',
        'email': 'x@y.com',
      });
      expect(user.emailVerified, isFalse);
      expect(user.providers, isEmpty);
      expect(user.profile, isNull);
      expect(user.metadata, isNull);
      expect(user.name, isNull);
      expect(user.avatarUrl, isNull);
      expect(user.createdAt, isNull);
    });
  });

  group('User round-trip', () {
    test('toJson then fromJson preserves fields', () {
      final original = User.fromJson(<String, dynamic>{
        'id': 'u-9',
        'email': 'r@t.com',
        'emailVerified': true,
        'providers': <dynamic>['email'],
        'profile': <String, dynamic>{'name': 'Bo'},
        'createdAt': '2026-01-02T03:04:05.000Z',
        'updatedAt': '2026-01-02T03:04:05.000Z',
      });

      final restored = User.fromJson(original.toJson());

      expect(restored.id, 'u-9');
      expect(restored.email, 'r@t.com');
      expect(restored.emailVerified, isTrue);
      expect(restored.providers, <String>['email']);
      expect(restored.name, 'Bo');
      expect(restored.createdAt, original.createdAt);
    });
  });
}
