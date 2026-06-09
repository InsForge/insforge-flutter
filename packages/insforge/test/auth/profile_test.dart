// packages/insforge_auth/test/profile_test.dart
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

void main() {
  group('Profile.fromJson', () {
    test('parses id + profile map', () {
      final p = Profile.fromJson(<String, dynamic>{
        'id': 'u-1',
        'profile': <String, dynamic>{'name': 'Ada', 'avatar_url': 'x'},
      });
      expect(p.id, 'u-1');
      expect(p.profile['name'], 'Ada');
      expect(p.profile['avatar_url'], 'x');
    });

    test('tolerates a null profile by yielding an empty map', () {
      final p = Profile.fromJson(<String, dynamic>{'id': 'u-2', 'profile': null});
      expect(p.id, 'u-2');
      expect(p.profile, isEmpty);
    });

    test('round-trips through toJson', () {
      final p = Profile.fromJson(<String, dynamic>{
        'id': 'u-3',
        'profile': <String, dynamic>{'bio': 'hi'},
      });
      final restored = Profile.fromJson(p.toJson());
      expect(restored.id, 'u-3');
      expect(restored.profile['bio'], 'hi');
    });
  });

  group('ResetTokenResponse.fromJson', () {
    test('parses token + expiresAt', () {
      final r = ResetTokenResponse.fromJson(<String, dynamic>{
        'token': 'reset-abc',
        'expiresAt': '2026-06-08T12:00:00.000Z',
      });
      expect(r.token, 'reset-abc');
      expect(r.expiresAt?.year, 2026);
      expect(r.expiresAt?.hour, 12);
    });

    test('tolerates a missing expiresAt', () {
      final r = ResetTokenResponse.fromJson(<String, dynamic>{
        'token': 'reset-only',
      });
      expect(r.token, 'reset-only');
      expect(r.expiresAt, isNull);
    });
  });
}
