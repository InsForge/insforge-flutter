// samples/twitter_app/lib/services/insforge_service.dart
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:insforge/insforge.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// Owns the singleton [InsforgeClient] and the OAuth deep-link flow.
class InsforgeService {
  InsforgeService()
      : client = InsforgeClient(
          AppConfig.backendUrl,
          AppConfig.anonKey,
          openRouterApiKey:
              AppConfig.aiEnabled ? AppConfig.openRouterApiKey : null,
          options: const InsforgeOptions(logLevel: LogLevel.info),
        );

  final InsforgeClient client;
  final AppLinks _appLinks = AppLinks();

  /// Restores any persisted session. Call once at startup.
  Future<void> restore() => client.restoreSession();

  /// Runs the full PKCE OAuth flow for [provider]:
  ///  1. generate a code verifier + challenge,
  ///  2. ask the SDK for the provider authorization URL,
  ///  3. open it in the system browser (`url_launcher`),
  ///  4. wait for the OS to deliver the redirect URI (`app_links`),
  ///  5. exchange the code (`handleOAuthCallback`) for a session.
  Future<AuthResponse> signInWithOAuth(OAuthProvider provider) async {
    final verifier = PkceHelper.generateCodeVerifier();
    final challenge = PkceHelper.codeChallenge(verifier);

    final authUrl = await client.auth.getOAuthUrl(
      provider: provider,
      redirectUri: AppConfig.oauthRedirectUri,
      codeChallenge: challenge,
    );

    // Start listening BEFORE launching so we don't miss a fast redirect.
    final redirectFuture = _waitForRedirect();

    final launched = await launchUrl(
      Uri.parse(authUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw InsforgeException('Could not launch the OAuth URL: $authUrl');
    }

    final redirectUri = await redirectFuture;
    return client.auth.handleOAuthCallback(redirectUri, verifier);
  }

  /// Completes with the first incoming deep link whose scheme matches the
  /// configured OAuth scheme.
  Future<Uri> _waitForRedirect() {
    final completer = Completer<Uri>();
    late final StreamSubscription<Uri> sub;
    sub = _appLinks.uriLinkStream.listen((Uri uri) {
      if (uri.scheme == AppConfig.oauthScheme && !completer.isCompleted) {
        completer.complete(uri);
        sub.cancel();
      }
    });
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        sub.cancel();
        throw InsforgeException('OAuth flow timed out');
      },
    );
  }

  Future<void> dispose() => client.dispose();
}
