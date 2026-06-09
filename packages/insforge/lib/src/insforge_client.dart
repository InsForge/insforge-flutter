// packages/insforge/lib/src/insforge_client.dart
import 'package:insforge/insforge.dart';

/// The unified InsForge client.
///
/// Constructs a single shared [InsforgeHttpClient] (used by `auth`, `database`,
/// `storage`, and `functions`) and a single [SessionStorage] (an
/// [InMemorySessionStorage] by default). Each module is exposed as a lazily
/// cached getter.
///
/// `ai` is the exception: per the SDK design, [AIClient] is a **standalone**
/// OpenRouter client constructed from [openRouterApiKey] (not the InsForge HTTP
/// client). When no key is supplied the [ai] getter throws a [StateError].
///
/// ### OAuth / deep links
/// The SDK provides [AuthClient.getOAuthUrl] and [AuthClient.handleOAuthCallback];
/// the host app performs the browser launch + redirect capture. A typical flow:
///
/// ```dart
/// final verifier = PkceHelper.generateCodeVerifier();
/// final challenge = PkceHelper.codeChallenge(verifier);
/// final url = await client.auth.getOAuthUrl(
///   provider: OAuthProvider.google,
///   redirectUri: 'myapp://auth-callback',
///   codeChallenge: challenge,
/// );
/// // launch `url` with url_launcher; capture the redirect Uri with app_links:
/// final session = await client.auth.handleOAuthCallback(redirectUri, verifier);
/// ```
class InsforgeClient {
  InsforgeClient(
    String baseUrl,
    String anonKey, {
    InsforgeOptions? options,
    String? apiKey,
    String? openRouterApiKey,
    SessionStorage? sessionStorage,
  })  : _openRouterApiKey = openRouterApiKey,
        sessionStorage = sessionStorage ?? InMemorySessionStorage(),
        http = InsforgeHttpClient(
          baseUrl: baseUrl,
          anonKey: anonKey,
          apiKey: apiKey,
          options: options ?? const InsforgeOptions(),
        );

  /// The shared HTTP transport used by every InsForge-backed module.
  final InsforgeHttpClient http;

  /// The session store backing [auth]. An [InMemorySessionStorage] by default.
  final SessionStorage sessionStorage;

  final String? _openRouterApiKey;

  AuthClient? _auth;
  DatabaseClient? _database;
  StorageClient? _storage;
  FunctionsClient? _functions;
  AIClient? _ai;

  /// Authentication: email/password, PKCE OAuth, sessions, profiles.
  ///
  /// Constructed with the shared [http] and [sessionStorage] so token writes
  /// propagate to the HTTP client's auth interceptor and persist across runs.
  AuthClient get auth => _auth ??= AuthClient(http, sessionStorage);

  /// PostgREST-style record CRUD + query builder.
  DatabaseClient get database => _database ??= DatabaseClient(http);

  /// Buckets and objects.
  StorageClient get storage => _storage ??= StorageClient(http);

  /// Edge-function invocation.
  FunctionsClient get functions => _functions ??= FunctionsClient(http);

  /// Standalone OpenRouter AI client.
  ///
  /// Throws a [StateError] when this client was created without an
  /// `openRouterApiKey`.
  AIClient get ai {
    final key = _openRouterApiKey;
    if (key == null || key.isEmpty) {
      throw StateError(
        'AI is unavailable: no openRouterApiKey was supplied to InsforgeClient. '
        'Pass openRouterApiKey (or Insforge.initialize(openRouterApiKey: ...)) '
        'with an OpenRouter API key to use client.ai.',
      );
    }
    return _ai ??= AIClient(key);
  }

  /// Restores any persisted session into [auth] (and the shared HTTP client).
  ///
  /// Call once at startup; [Insforge.initialize] does this for you.
  Future<Session?> restoreSession() => auth.restoreSession();

  /// Releases held resources (closes the auth state stream).
  Future<void> dispose() async {
    await _auth?.dispose();
  }
}
