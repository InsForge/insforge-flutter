// packages/insforge_auth/test/enums_test.dart
import 'package:insforge_auth/insforge_auth.dart';
import 'package:test/test.dart';

void main() {
  group('OAuthProvider', () {
    test('exposes the eleven supported providers with wire names', () {
      expect(OAuthProvider.values.length, 11);
      expect(OAuthProvider.google.wireName, 'google');
      expect(OAuthProvider.github.wireName, 'github');
      expect(OAuthProvider.discord.wireName, 'discord');
      expect(OAuthProvider.linkedin.wireName, 'linkedin');
      expect(OAuthProvider.facebook.wireName, 'facebook');
      expect(OAuthProvider.instagram.wireName, 'instagram');
      expect(OAuthProvider.tiktok.wireName, 'tiktok');
      expect(OAuthProvider.apple.wireName, 'apple');
      expect(OAuthProvider.x.wireName, 'x');
      expect(OAuthProvider.spotify.wireName, 'spotify');
      expect(OAuthProvider.microsoft.wireName, 'microsoft');
    });
  });

  group('ClientType', () {
    test('exposes wire names and defaults conceptually to mobile', () {
      expect(ClientType.web.wireName, 'web');
      expect(ClientType.mobile.wireName, 'mobile');
      expect(ClientType.desktop.wireName, 'desktop');
      expect(ClientType.server.wireName, 'server');
    });
  });

  group('AuthChangeEvent', () {
    test('exposes the four lifecycle events', () {
      expect(AuthChangeEvent.values, <AuthChangeEvent>[
        AuthChangeEvent.signedIn,
        AuthChangeEvent.signedOut,
        AuthChangeEvent.tokenRefreshed,
        AuthChangeEvent.userUpdated,
      ]);
    });
  });
}
