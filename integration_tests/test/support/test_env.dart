// integration_tests/test/support/test_env.dart
//
// Environment-driven configuration and client factories for the live-backend
// integration suite. Everything is read from `Platform.environment`, so with
// NO env vars set every integration test SKIPS (safe for normal CI).
import 'dart:io';

import 'package:insforge/insforge.dart';

/// Fallback password used for freshly created (self-registered) users.
const String testPassword = 'Test_P@ssword_123!';

/// Reads integration configuration from environment variables and exposes
/// "configured?" predicates plus client factories.
///
/// Env vars:
///   INSFORGE_INTEGRATION_BASE_URL       – required for everything
///   INSFORGE_INTEGRATION_ANON_KEY       – required for everything
///   INSFORGE_INTEGRATION_API_KEY        – required for storage
///   INSFORGE_INTEGRATION_TEST_EMAIL     – required for authed modules
///   INSFORGE_INTEGRATION_TEST_PASSWORD  – required for authed modules
///   INSFORGE_INTEGRATION_OPENROUTER_KEY – required for AI
class TestEnv {
  TestEnv._();

  static final TestEnv instance = TestEnv._();

  String? _read(String key) {
    final value = Platform.environment[key];
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Base URL of the InsForge project, trailing slashes stripped.
  String? get baseUrl {
    final raw = _read('INSFORGE_INTEGRATION_BASE_URL');
    if (raw == null) return null;
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  String? get anonKey => _read('INSFORGE_INTEGRATION_ANON_KEY');
  String? get apiKey => _read('INSFORGE_INTEGRATION_API_KEY');
  String? get testEmail => _read('INSFORGE_INTEGRATION_TEST_EMAIL');
  String? get testPassword => _read('INSFORGE_INTEGRATION_TEST_PASSWORD');
  String? get openRouterKey => _read('INSFORGE_INTEGRATION_OPENROUTER_KEY');

  // ---------------------------------------------------------------------------
  // Configuration predicates + skip reasons
  // ---------------------------------------------------------------------------

  /// True when the minimum core config (base URL + anon key) is present.
  bool get coreConfigured => baseUrl != null && anonKey != null;

  /// A human-readable reason the core suite is skipped, or null when configured.
  String? get coreSkipReason {
    final missing = <String>[
      if (baseUrl == null) 'INSFORGE_INTEGRATION_BASE_URL',
      if (anonKey == null) 'INSFORGE_INTEGRATION_ANON_KEY',
    ];
    if (missing.isEmpty) return null;
    return 'Integration env not configured – set ${missing.join(', ')}.';
  }

  /// True when core config + a fixed pre-verified test account are present.
  bool get authConfigured =>
      coreConfigured && testEmail != null && testPassword != null;

  String? get authSkipReason {
    if (coreSkipReason != null) return coreSkipReason;
    final missing = <String>[
      if (testEmail == null) 'INSFORGE_INTEGRATION_TEST_EMAIL',
      if (testPassword == null) 'INSFORGE_INTEGRATION_TEST_PASSWORD',
    ];
    if (missing.isEmpty) return null;
    return 'Authenticated integration tests need a pre-verified account – '
        'set ${missing.join(', ')}.';
  }

  /// True when core config + the project API key (required by storage) exist.
  bool get storageConfigured => coreConfigured && apiKey != null;

  String? get storageSkipReason {
    if (coreSkipReason != null) return coreSkipReason;
    if (apiKey == null) {
      return 'Storage integration tests need the project API key – '
          'set INSFORGE_INTEGRATION_API_KEY.';
    }
    return null;
  }

  /// True when an OpenRouter API key is present (AI is standalone).
  bool get aiConfigured => openRouterKey != null;

  String? get aiSkipReason {
    if (openRouterKey == null) {
      return 'AI integration tests need an OpenRouter key – '
          'set INSFORGE_INTEGRATION_OPENROUTER_KEY.';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Client factories
  // ---------------------------------------------------------------------------

  /// Builds a fresh [InsforgeHttpClient] for the configured project.
  ///
  /// Pass [withApiKey] to attach the project API key (required by storage).
  /// Callers must only invoke this once [coreConfigured] (and, for
  /// [withApiKey], [storageConfigured]) is true.
  InsforgeHttpClient newHttpClient({bool withApiKey = false}) {
    final base = baseUrl;
    final anon = anonKey;
    if (base == null || anon == null) {
      throw StateError(
        'newHttpClient called without core configuration. $coreSkipReason',
      );
    }
    return InsforgeHttpClient(
      baseUrl: base,
      anonKey: anon,
      apiKey: withApiKey ? apiKey : null,
    );
  }

  /// Signs in with the fixed pre-verified test account and returns the HTTP
  /// client, now carrying the authenticated user's access token.
  ///
  /// Throws a clear [StateError] when not configured or when sign-in fails.
  Future<InsforgeHttpClient> signedInHttpClient() async {
    if (!authConfigured) {
      throw StateError('signedInHttpClient called without auth configuration. '
          '$authSkipReason');
    }
    final http = newHttpClient();
    final auth = AuthClient(http, InMemorySessionStorage());
    try {
      await auth.signIn(email: testEmail!, password: testPassword!);
    } catch (e) {
      throw StateError(
        'Failed to sign in with the fixed integration test account '
        '($testEmail). Ensure INSFORGE_INTEGRATION_TEST_EMAIL / '
        'INSFORGE_INTEGRATION_TEST_PASSWORD name a pre-verified account. '
        'Cause: $e',
      );
    }
    return http;
  }

  /// A unique email for self-registration, salted with the current timestamp.
  String uniqueEmail([String prefix = 'sdktest']) {
    final ts = DateTime.now().microsecondsSinceEpoch;
    return '$prefix+$ts@test.insforge.dev';
  }
}

/// Shared accessor used by every test file.
final TestEnv env = TestEnv.instance;
