// samples/twitter_app/lib/config.dart

/// App configuration. Replace the placeholders with your InsForge project's
/// values before running. See README.md for where to find each value.
class AppConfig {
  AppConfig._();

  /// Your InsForge project base URL (no module path, no trailing slash).
  /// Local dev example: `http://10.0.2.2:7130` (Android emulator → host).
  static const String backendUrl = 'http://localhost:7130';

  /// Your project's anon (public) key.
  static const String anonKey = 'REPLACE_WITH_ANON_KEY';

  /// Optional OpenRouter API key enabling the "suggest a caption" AI feature.
  /// Leave empty to disable AI (the Compose screen hides the button).
  static const String openRouterApiKey = '';

  /// The custom URI scheme used for the OAuth redirect. Must match the
  /// per-platform deep-link config in android/ and ios/ (see README).
  static const String oauthScheme = 'insforgetwitter';

  /// The full redirect URI passed to getOAuthUrl and registered with the OS.
  static const String oauthRedirectUri = '$oauthScheme://auth-callback';

  /// Whether the AI feature is configured.
  static bool get aiEnabled => openRouterApiKey.isNotEmpty;
}
