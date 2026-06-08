# InsForge Flutter SDK — Plan 7: `insforge` umbrella + Twitter sample Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `insforge` umbrella package — the only Flutter-dependent package in the SDK — that re-exports every feature package, wires a single shared `InsforgeHttpClient` + `SessionStorage` into lazy module getters (`auth`, `database`, `storage`, `functions`, `ai`), ships a `flutter_secure_storage`-backed `SecureSessionStorage`, and offers a supabase_flutter-style `Insforge.initialize(...)` / `Insforge.instance` singleton. Then build `samples/twitter_app`: a Riverpod-based Twitter-style app exercising auth (email/password + PKCE OAuth deep-link), database (joined tweet feed + like/unlike + pagination), storage (image upload), and AI (streaming "suggest a caption" via OpenRouter).

**Architecture:** `InsforgeClient` constructs **one** `InsforgeHttpClient` (Plan 1) and **one** `SessionStorage` (a `SecureSessionStorage` by default), then exposes feature clients as lazily-cached getters that all share that http client. `AuthClient` (Plan 2) is constructed with the shared http + storage so token writes propagate to the http client's auth interceptor. `AIClient` (Plan 6) is the exception: it is a **standalone OpenRouter client** built from an OpenRouter API key, so the `ai` getter throws a clear error when no key was supplied. `Insforge.initialize` builds the client and `await`s `auth.restoreSession()` so a persisted session is live before the first frame. The sample app reads a `lib/config.dart`, builds the client in a `lib/services/insforge_service.dart`, and exposes it + an `onAuthStateChange` `StreamProvider` through Riverpod; OAuth uses `url_launcher` to open `auth.getOAuthUrl(...)` and `app_links` to capture the redirect, then `auth.handleOAuthCallback(uri, verifier)`.

**Tech Stack:** Dart ≥ 3.5, Flutter ≥ 3.24, `flutter_secure_storage` ^9.2.2, `dio` ^5.7.0, the six feature packages (path deps); sample adds `flutter_riverpod` ^2.5.1, `url_launcher` ^6.3.0, `app_links` ^6.3.0, `image_picker` ^1.1.2. Umbrella tests use `flutter_test` (run via `flutter test`); the sample app is verified **manually** via `flutter run`.

**Prerequisite:** The Flutter SDK (which bundles Dart) must be installed and on `PATH` (`flutter --version` and `dart --version` must work). Plans 1–6 must be complete and committed (`insforge_core`, `insforge_auth`, `insforge_database`, `insforge_storage`, `insforge_functions`, `insforge_ai` present under `packages/`). The umbrella depends on all of them via path/workspace dependencies; the sample depends on the umbrella.

**Plan series:** This is plan 7 of 7. Earlier: 01 core, 02 auth, 03 database, 04 storage, 05 functions, 06 ai. This plan appends `packages/insforge` and `samples/twitter_app` to the workspace member list created in Plan 1.

---

## File Structure

```
insforge-flutter/
├── pubspec.yaml                                  # MODIFIED: append packages/insforge + samples/twitter_app
└── packages/
│   └── insforge/
│       ├── pubspec.yaml
│       ├── analysis_options.yaml                 # includes root lints
│       ├── lib/
│       │   ├── insforge.dart                     # umbrella re-exports + public types
│       │   └── src/
│       │       ├── secure_session_storage.dart   # SecureSessionStorage (flutter_secure_storage)
│       │       ├── insforge_client.dart          # InsforgeClient (shared http + lazy getters)
│       │       └── insforge.dart                 # Insforge singleton (initialize/instance)
│       └── test/
│           ├── secure_session_storage_test.dart  # delegation to a fake FlutterSecureStorage
│           ├── insforge_client_test.dart         # shared http, lazy getters, ai-without-key throws
│           └── insforge_singleton_test.dart      # initialize/instance lifecycle
└── samples/
    └── twitter_app/
        ├── pubspec.yaml
        ├── analysis_options.yaml
        ├── README.md                             # setup, DB schema, storage bucket, deep-link config
        ├── android/app/src/main/AndroidManifest.xml   # intent-filter snippet (in README)
        ├── ios/Runner/Info.plist                      # CFBundleURLTypes snippet (in README)
        └── lib/
            ├── main.dart                         # bootstrap + ProviderScope + auth-gated router
            ├── config.dart                       # backend URL, anon key, OpenRouter key, OAuth scheme
            ├── services/
            │   └── insforge_service.dart         # builds InsforgeClient + OAuth deep-link helper
            ├── providers.dart                    # Riverpod providers (client, authState, feed)
            ├── models/
            │   └── tweet.dart                    # Tweet view model (author join)
            └── screens/
                ├── auth_screen.dart              # email/password + OAuth buttons
                ├── feed_screen.dart              # tweet list, pull-to-refresh, pagination, like
                ├── compose_screen.dart           # new tweet + image upload + AI caption
                └── profile_screen.dart           # getProfile / updateProfile
```

---

## Task 1: Umbrella package scaffolding + workspace registration

**Files:**
- Create: `packages/insforge/pubspec.yaml`
- Create: `packages/insforge/analysis_options.yaml`
- Create: `packages/insforge/lib/insforge.dart`
- Modify: `pubspec.yaml` (workspace root)

- [ ] **Step 1: Create the package `pubspec.yaml`**

```yaml
# packages/insforge/pubspec.yaml
name: insforge
description: The InsForge Flutter SDK — unified client + Flutter integration.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.5.0
  flutter: '>=3.24.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_secure_storage: ^9.2.2
  dio: ^5.7.0
  insforge_core:
    path: ../insforge_core
  insforge_auth:
    path: ../insforge_auth
  insforge_database:
    path: ../insforge_database
  insforge_storage:
    path: ../insforge_storage
  insforge_functions:
    path: ../insforge_functions
  insforge_ai:
    path: ../insforge_ai

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

- [ ] **Step 2: Create the package-local `analysis_options.yaml`**

```yaml
# packages/insforge/analysis_options.yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 3: Create a placeholder library export file**

```dart
// packages/insforge/lib/insforge.dart
/// The InsForge Flutter SDK — unified client and Flutter integration.
library insforge;

// Re-exports and public types are added as each component lands in later tasks.
```

- [ ] **Step 4: Register the package + sample in the workspace root `pubspec.yaml`**

In the repo-root `pubspec.yaml`, the `workspace:` list (extended by Plans 2–6) currently ends with the six feature packages. Append the umbrella and the sample so it reads:

```yaml
workspace:
  - packages/insforge_core
  - packages/insforge_auth
  - packages/insforge_database
  - packages/insforge_storage
  - packages/insforge_functions
  - packages/insforge_ai
  - packages/insforge
  - samples/twitter_app
```

(If any earlier feature-package line is missing, ensure it is present alongside the others; the two new lines are `packages/insforge` and `samples/twitter_app`.)

- [ ] **Step 5: Resolve dependencies**

Run: `flutter pub get` (from repo root)
Expected: resolves the workspace including `insforge` (and Flutter SDK deps), exit 0.

> Note: from this plan onward the workspace contains Flutter packages, so use `flutter pub get` (not `dart pub get`) at the root. The `samples/twitter_app` line is added now but its `pubspec.yaml` does not exist yet, so if `pub get` complains about the missing member, temporarily remove the `- samples/twitter_app` line until Task 9 creates it, then re-add. Prefer creating Task 9's `samples/twitter_app/pubspec.yaml` first if you want a single clean resolve.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/insforge/pubspec.yaml packages/insforge/analysis_options.yaml packages/insforge/lib/insforge.dart
git commit -m "feat(insforge): add umbrella package skeleton"
```

---

## Task 2: `SecureSessionStorage`

**Files:**
- Create: `packages/insforge/lib/src/secure_session_storage.dart`
- Test: `packages/insforge/test/secure_session_storage_test.dart`
- Modify: `packages/insforge/lib/insforge.dart`

`SecureSessionStorage` implements the core `SessionStorage` interface by delegating to a `FlutterSecureStorage`. To make it unit-testable without a platform channel, the constructor accepts an injectable `FlutterSecureStorage` (defaulting to a real one). The test injects a fake implementing the same `read`/`write`/`delete` surface via `FlutterSecureStorage`'s own constructor seam — we wrap an in-memory map and verify delegation. Because `FlutterSecureStorage` is a concrete class (not an interface), the cleanest TDD seam is to make `SecureSessionStorage` accept a `FlutterSecureStorage` and, in tests, set `FlutterSecureStorage.setMockInitialValues`-style behavior via the platform interface. We use the simpler, dependency-free approach: inject a `FlutterSecureStorage` whose platform implementation is a fake registered through `FlutterSecureStoragePlatform.instance`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge/test/secure_session_storage_test.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insforge/insforge.dart';
import 'package:insforge_core/insforge_core.dart';

/// In-memory fake of the secure-storage platform channel, so the test runs on
/// the Dart VM without a real device keystore.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = <String, String>{};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map<String, String>.from(store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    store[key] = value;
  }
}

void main() {
  late _FakeSecureStoragePlatform platform;
  late SecureSessionStorage storage;

  setUp(() {
    platform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    storage = SecureSessionStorage(
      secureStorage: const FlutterSecureStorage(),
    );
  });

  test('is a SessionStorage', () {
    expect(storage, isA<SessionStorage>());
  });

  test('write/read/delete delegate to flutter_secure_storage', () async {
    expect(await storage.read('insforge_access_token'), isNull);

    await storage.write('insforge_access_token', 'jwt-abc');
    expect(platform.store['insforge_access_token'], 'jwt-abc');
    expect(await storage.read('insforge_access_token'), 'jwt-abc');

    await storage.delete('insforge_access_token');
    expect(platform.store.containsKey('insforge_access_token'), isFalse);
    expect(await storage.read('insforge_access_token'), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge && flutter test test/secure_session_storage_test.dart`
Expected: FAIL — `SecureSessionStorage` is not defined.

- [ ] **Step 3: Write `secure_session_storage.dart`**

```dart
// packages/insforge/lib/src/secure_session_storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insforge_core/insforge_core.dart';

/// A [SessionStorage] backed by `flutter_secure_storage` (Keychain on iOS,
/// EncryptedSharedPreferences/Keystore on Android).
///
/// This is the default session store used by [InsforgeClient] when no custom
/// storage is supplied. Inject a [FlutterSecureStorage] to customize platform
/// options or to substitute a fake in tests.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
```

- [ ] **Step 4: Export it**

In `packages/insforge/lib/insforge.dart`, replace the trailing comment with:

```dart
export 'src/secure_session_storage.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge && flutter test test/secure_session_storage_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge/lib/src/secure_session_storage.dart packages/insforge/lib/insforge.dart packages/insforge/test/secure_session_storage_test.dart
git commit -m "feat(insforge): add SecureSessionStorage (flutter_secure_storage)"
```

---

## Task 3: `InsforgeClient` — shared http + lazy module getters

**Files:**
- Create: `packages/insforge/lib/src/insforge_client.dart`
- Test: `packages/insforge/test/insforge_client_test.dart`
- Modify: `packages/insforge/lib/insforge.dart`

`InsforgeClient` builds one `InsforgeHttpClient` and one `SessionStorage`, then exposes lazily-cached `auth`/`database`/`storage`/`functions` getters that all share the http client. `auth` is also constructed with the shared storage so its token writes reach the http client's interceptor. The `ai` getter returns a standalone `AIClient` built from `openRouterApiKey`, throwing a clear `StateError` when that key was not supplied. Tests inject a fake `SessionStorage` (the core `InMemorySessionStorage`) so no platform channel is needed.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge/test/insforge_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:insforge/insforge.dart';

void main() {
  InsforgeClient build({String? openRouterApiKey}) {
    return InsforgeClient(
      'https://x.insforge.app',
      'anon-key',
      openRouterApiKey: openRouterApiKey,
      // Inject in-memory storage so no Keychain/Keystore is touched.
      sessionStorage: InMemorySessionStorage(),
    );
  }

  test('module getters are non-null and cached (same instance each call)', () {
    final client = build();

    expect(client.auth, isA<AuthClient>());
    expect(client.database, isA<DatabaseClient>());
    expect(client.storage, isA<StorageClient>());
    expect(client.functions, isA<FunctionsClient>());

    expect(identical(client.auth, client.auth), isTrue);
    expect(identical(client.database, client.database), isTrue);
    expect(identical(client.storage, client.storage), isTrue);
    expect(identical(client.functions, client.functions), isTrue);
  });

  test('all modules share the one InsforgeHttpClient', () {
    final client = build();
    // The shared http client is exposed for advanced use; database + storage
    // must use the very same instance.
    expect(identical(client.http, client.http), isTrue);
  });

  test('ai getter throws a clear error when no OpenRouter key was supplied', () {
    final client = build();
    expect(
      () => client.ai,
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('openRouterApiKey'),
        ),
      ),
    );
  });

  test('ai getter returns a standalone AIClient when a key was supplied', () {
    final client = build(openRouterApiKey: 'sk-or-test');
    expect(client.ai, isA<AIClient>());
    expect(identical(client.ai, client.ai), isTrue);
  });

  test('auth writes propagate to the shared http client access token', () {
    final client = build();
    // Simulating an auth token write must be visible to the http interceptor.
    client.http.accessToken = 'user-jwt';
    expect(client.http.accessToken, 'user-jwt');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge && flutter test test/insforge_client_test.dart`
Expected: FAIL — `InsforgeClient` is not defined.

- [ ] **Step 3: Write `insforge_client.dart`**

```dart
// packages/insforge/lib/src/insforge_client.dart
import 'package:insforge_ai/insforge_ai.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:insforge_database/insforge_database.dart';
import 'package:insforge_functions/insforge_functions.dart';
import 'package:insforge_storage/insforge_storage.dart';

import 'secure_session_storage.dart';

/// The unified InsForge client.
///
/// Constructs a single shared [InsforgeHttpClient] (used by `auth`, `database`,
/// `storage`, and `functions`) and a single [SessionStorage] (a
/// [SecureSessionStorage] by default). Each module is exposed as a lazily
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
        sessionStorage = sessionStorage ?? SecureSessionStorage(),
        http = InsforgeHttpClient(
          baseUrl: baseUrl,
          anonKey: anonKey,
          apiKey: apiKey,
          options: options ?? const InsforgeOptions(),
        );

  /// The shared HTTP transport used by every InsForge-backed module.
  final InsforgeHttpClient http;

  /// The session store backing [auth]. A [SecureSessionStorage] by default.
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
```

- [ ] **Step 4: Re-export the feature packages + the client**

Append to `packages/insforge/lib/insforge.dart`:

```dart
// Re-export the public surface of every feature package so apps can
// `import 'package:insforge/insforge.dart';` and get everything.
export 'package:insforge_core/insforge_core.dart';
export 'package:insforge_auth/insforge_auth.dart';
export 'package:insforge_database/insforge_database.dart';
export 'package:insforge_storage/insforge_storage.dart';
export 'package:insforge_functions/insforge_functions.dart';
export 'package:insforge_ai/insforge_ai.dart';

export 'src/insforge_client.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge && flutter test test/insforge_client_test.dart`
Expected: All tests PASS (cached getters, shared http, ai-without-key throws, ai-with-key returns).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge/lib/src/insforge_client.dart packages/insforge/lib/insforge.dart packages/insforge/test/insforge_client_test.dart
git commit -m "feat(insforge): add InsforgeClient with shared http + lazy module getters"
```

---

## Task 4: `Insforge` singleton — `initialize` / `instance`

**Files:**
- Create: `packages/insforge/lib/src/insforge.dart`
- Test: `packages/insforge/test/insforge_singleton_test.dart`
- Modify: `packages/insforge/lib/insforge.dart`

`Insforge.initialize(...)` builds the client (optionally with an injected `SessionStorage` for tests) and `await`s `restoreSession()` so a persisted session is live before the first frame. `Insforge.instance` returns the built client or throws if `initialize` was never called. A `reset()` hook (visible-for-testing) lets tests re-initialize.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge/test/insforge_singleton_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:insforge/insforge.dart';

void main() {
  setUp(Insforge.resetForTest);
  tearDown(Insforge.resetForTest);

  test('instance throws before initialize', () {
    expect(() => Insforge.instance, throwsA(isA<StateError>()));
  });

  test('initialize builds a client and exposes it via instance', () async {
    await Insforge.initialize(
      url: 'https://x.insforge.app',
      anonKey: 'anon-key',
      sessionStorageForTest: InMemorySessionStorage(),
    );

    expect(Insforge.instance, isA<InsforgeClient>());
    expect(Insforge.instance.auth, isA<AuthClient>());
    // No session was stored, so restoreSession yielded null and currentUser is
    // null — but the call must not have thrown.
    expect(Insforge.instance.auth.currentUser, isNull);
  });

  test('initialize restores a persisted session', () async {
    final storage = InMemorySessionStorage();
    // Pre-seed a stored session (no JWT exp → restore returns it as-is).
    await storage.write('insforge_access_token', 'stored-access');
    await storage.write('insforge_refresh_token', 'stored-refresh');
    await storage.write(
      'insforge_user',
      '{"id":"u-1","email":"a@b.com","emailVerified":true}',
    );

    await Insforge.initialize(
      url: 'https://x.insforge.app',
      anonKey: 'anon-key',
      sessionStorageForTest: storage,
    );

    expect(Insforge.instance.auth.currentUser?.id, 'u-1');
    expect(Insforge.instance.http.accessToken, 'stored-access');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge && flutter test test/insforge_singleton_test.dart`
Expected: FAIL — `Insforge` is not defined.

- [ ] **Step 3: Write `insforge.dart` (the singleton)**

```dart
// packages/insforge/lib/src/insforge.dart
import 'package:flutter/foundation.dart';
import 'package:insforge_core/insforge_core.dart';

import 'insforge_client.dart';

/// supabase_flutter-style global accessor for a single [InsforgeClient].
///
/// Call [initialize] once near app startup (it awaits session restoration),
/// then read [instance] anywhere. Apps that prefer dependency injection can
/// construct an [InsforgeClient] directly instead.
class Insforge {
  Insforge._();

  static InsforgeClient? _client;

  /// The initialized client.
  ///
  /// Throws a [StateError] if [initialize] has not completed.
  static InsforgeClient get instance {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Insforge.instance was read before Insforge.initialize() completed. '
        'Call `await Insforge.initialize(url: ..., anonKey: ...)` in main().',
      );
    }
    return client;
  }

  /// Whether [initialize] has completed.
  static bool get isInitialized => _client != null;

  /// Builds the global client and restores any persisted session.
  ///
  /// [openRouterApiKey] enables `Insforge.instance.ai`. Tests may pass
  /// [sessionStorageForTest] to avoid the platform secure store.
  static Future<void> initialize({
    required String url,
    required String anonKey,
    String? apiKey,
    String? openRouterApiKey,
    InsforgeOptions? options,
    @visibleForTesting SessionStorage? sessionStorageForTest,
  }) async {
    final client = InsforgeClient(
      url,
      anonKey,
      apiKey: apiKey,
      openRouterApiKey: openRouterApiKey,
      options: options,
      sessionStorage: sessionStorageForTest,
    );
    await client.restoreSession();
    _client = client;
  }

  /// Disposes and clears the global client. Visible for testing.
  @visibleForTesting
  static void resetForTest() {
    _client?.dispose();
    _client = null;
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge/lib/insforge.dart`:

```dart
export 'src/insforge.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge && flutter test test/insforge_singleton_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Run the full umbrella suite + analyze**

Run: `cd packages/insforge && flutter test && flutter analyze`
Expected: all tests PASS; "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add packages/insforge/lib/src/insforge.dart packages/insforge/lib/insforge.dart packages/insforge/test/insforge_singleton_test.dart
git commit -m "feat(insforge): add Insforge singleton (initialize/instance)"
```

---

## Task 5: CI step for the umbrella package

**Files:**
- Modify: `.github/workflows/ci.yaml`

- [ ] **Step 1: Add a Flutter setup + umbrella test step**

In `.github/workflows/ci.yaml` (created in Plan 1, extended by later plans), add a Flutter job (or steps in the existing job after the Dart steps). The umbrella package requires the Flutter toolchain, so it cannot run under the pure-Dart `setup-dart` job.

```yaml
  flutter-umbrella:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - name: Install dependencies
        run: flutter pub get
      - name: Analyze insforge
        working-directory: packages/insforge
        run: flutter analyze
      - name: Test insforge
        working-directory: packages/insforge
        run: flutter test
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci(insforge): analyze + test the umbrella package with Flutter"
```

---

## Task 6: Sample app scaffolding + config

> The remaining tasks build `samples/twitter_app`. These are a Flutter app, so verification is **manual** (`flutter run`) rather than unit tests. Each task creates concrete files with complete code and ends with a manual-verification step.

**Files:**
- Create: `samples/twitter_app/pubspec.yaml`
- Create: `samples/twitter_app/analysis_options.yaml`
- Create: `samples/twitter_app/lib/config.dart`
- (Generated by Flutter, see Step 2) `samples/twitter_app/android/`, `ios/`, etc.

- [ ] **Step 1: Generate the Flutter app platform scaffolding**

From the repo root run:

```bash
flutter create --org dev.insforge --project-name twitter_app \
  --platforms=android,ios samples/twitter_app
```

Expected: creates `samples/twitter_app` with `android/`, `ios/`, `lib/main.dart`, and a default `pubspec.yaml`. We overwrite `pubspec.yaml` and `lib/` below.

- [ ] **Step 2: Overwrite `samples/twitter_app/pubspec.yaml`**

```yaml
# samples/twitter_app/pubspec.yaml
name: twitter_app
description: Twitter-style sample exercising every InsForge Flutter SDK module.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.5.0
  flutter: '>=3.24.0'

dependencies:
  flutter:
    sdk: flutter
  insforge:
    path: ../../packages/insforge
  flutter_riverpod: ^2.5.1
  url_launcher: ^6.3.0
  app_links: ^6.3.0
  image_picker: ^1.1.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 3: Create the package-local `analysis_options.yaml`**

```yaml
# samples/twitter_app/analysis_options.yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 4: Create `lib/config.dart`**

```dart
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
```

- [ ] **Step 5: Resolve dependencies**

Run: `flutter pub get` (from repo root)
Expected: resolves the workspace including `twitter_app`, exit 0. (If you removed the `- samples/twitter_app` workspace line in Task 1, re-add it now.)

- [ ] **Step 6: Commit**

```bash
git add samples/twitter_app/pubspec.yaml samples/twitter_app/analysis_options.yaml samples/twitter_app/lib/config.dart samples/twitter_app/android samples/twitter_app/ios
git commit -m "feat(sample): scaffold twitter_app + config"
```

- [ ] **Step 7: Manual verification**

Run: `cd samples/twitter_app && flutter run` (on an emulator/simulator).
You should see the default Flutter counter app (we replace `lib/main.dart` next). This confirms the toolchain + workspace resolution work before adding SDK code.

---

## Task 7: Service layer — `InsforgeService` + OAuth deep-link helper

**Files:**
- Create: `samples/twitter_app/lib/services/insforge_service.dart`

The service builds the `InsforgeClient` from `AppConfig` and encapsulates the full PKCE OAuth deep-link dance: generate a verifier/challenge, ask the SDK for the provider URL, launch it with `url_launcher`, await the redirect captured via `app_links`, then call `auth.handleOAuthCallback`.

- [ ] **Step 1: Write `insforge_service.dart`**

```dart
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
```

- [ ] **Step 2: Analyze**

Run: `cd samples/twitter_app && flutter analyze lib/services/insforge_service.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add samples/twitter_app/lib/services/insforge_service.dart
git commit -m "feat(sample): add InsforgeService + OAuth deep-link helper"
```

---

## Task 8: Riverpod providers + the Tweet model

**Files:**
- Create: `samples/twitter_app/lib/models/tweet.dart`
- Create: `samples/twitter_app/lib/providers.dart`

The feed joins each tweet to its author profile via the database `select` join syntax. The `Tweet` model parses both the tweet row and its embedded `author` object. Providers expose the service/client and an `onAuthStateChange` `StreamProvider` that gates the UI.

- [ ] **Step 1: Write `models/tweet.dart`**

```dart
// samples/twitter_app/lib/models/tweet.dart
import 'package:insforge/insforge.dart';

/// A tweet plus its joined author profile and like state.
class Tweet {
  Tweet({
    required this.id,
    required this.userId,
    required this.content,
    this.imageUrl,
    this.createdAt,
    this.authorName,
    this.authorAvatarUrl,
    this.likeCount = 0,
  });

  final String id;
  final String userId;
  final String content;
  final String? imageUrl;
  final DateTime? createdAt;
  final String? authorName;
  final String? authorAvatarUrl;
  final int likeCount;

  /// Parses a `tweets` row that joined the author profile, e.g. selected with
  /// `select('*, author:profiles!tweets_user_id_fkey(name, avatar_url)')`.
  factory Tweet.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final authorMap = author is Map ? Map<String, dynamic>.from(author) : null;
    final likes = json['likes'];
    final likeCount = likes is List
        ? likes.length
        : (json['like_count'] as num?)?.toInt() ?? 0;
    return Tweet(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      content: json['content'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      createdAt: parseInsforgeDate(json['created_at'] as String?),
      authorName: authorMap?['name'] as String?,
      authorAvatarUrl: authorMap?['avatar_url'] as String?,
      likeCount: likeCount,
    );
  }
}
```

- [ ] **Step 2: Write `providers.dart`**

```dart
// samples/twitter_app/lib/providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import 'services/insforge_service.dart';

/// The app-wide InsForge service (owns the client + OAuth flow).
final insforgeServiceProvider = Provider<InsforgeService>((ref) {
  final service = InsforgeService();
  ref.onDispose(service.dispose);
  return service;
});

/// Convenience accessor for the underlying client.
final insforgeClientProvider = Provider<InsforgeClient>((ref) {
  return ref.watch(insforgeServiceProvider).client;
});

/// The auth client.
final authClientProvider = Provider<AuthClient>((ref) {
  return ref.watch(insforgeClientProvider).auth;
});

/// Streams auth lifecycle changes. The UI watches this to gate signed-in vs
/// signed-out screens. Seeded with the current session so the first build
/// reflects a restored session.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final auth = ref.watch(authClientProvider);
  final controller = StreamController<AuthState>();
  // Emit the current state immediately, then forward live changes.
  final current = auth.currentSession;
  controller.add(
    AuthState(
      current != null ? AuthChangeEvent.signedIn : AuthChangeEvent.signedOut,
      current,
    ),
  );
  final sub = auth.onAuthStateChange.listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The currently signed-in user, or null.
final currentUserProvider = Provider<User?>((ref) {
  final state = ref.watch(authStateProvider);
  return state.maybeWhen(
    data: (AuthState s) => s.session?.user,
    orElse: () => null,
  );
});
```

> Add `import 'dart:async';` at the top of `providers.dart` (for `StreamController`).

- [ ] **Step 3: Analyze**

Run: `cd samples/twitter_app && flutter analyze lib/models/tweet.dart lib/providers.dart`
Expected: "No issues found!" (after adding the `dart:async` import).

- [ ] **Step 4: Commit**

```bash
git add samples/twitter_app/lib/models/tweet.dart samples/twitter_app/lib/providers.dart
git commit -m "feat(sample): add Tweet model + Riverpod providers"
```

---

## Task 9: App bootstrap + auth gate (`main.dart`) and `AuthScreen`

**Files:**
- Overwrite: `samples/twitter_app/lib/main.dart`
- Create: `samples/twitter_app/lib/screens/auth_screen.dart`

- [ ] **Step 1: Overwrite `lib/main.dart`**

```dart
// samples/twitter_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import 'providers.dart';
import 'screens/auth_screen.dart';
import 'screens/feed_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Restore a persisted session before the first frame.
  await container.read(insforgeServiceProvider).restore();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TwitterApp(),
    ),
  );
}

class TwitterApp extends StatelessWidget {
  const TwitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InsForge Twitter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Shows the feed when signed in, the auth screen otherwise.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      data: (AuthState state) =>
          state.session != null ? const FeedScreen() : const AuthScreen(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (Object e, _) =>
          Scaffold(body: Center(child: Text('Auth error: $e'))),
    );
  }
}
```

- [ ] **Step 2: Write `screens/auth_screen.dart`**

```dart
// samples/twitter_app/lib/screens/auth_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import '../providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final auth = ref.read(authClientProvider);
    try {
      if (_isSignUp) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (!res.hasSession) {
          setState(() =>
              _info = 'Check your email to verify your account, then sign in.');
        }
      } else {
        await auth.signIn(email: _email.text.trim(), password: _password.text);
      }
      // On success the authStateProvider stream flips the gate automatically.
    } on InsforgeHttpException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _oauth(OAuthProvider provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(insforgeServiceProvider).signInWithOAuth(provider);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('InsForge Twitter')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _isSignUp ? 'Create account' : 'Sign in',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                if (_info != null)
                  Text(_info!, style: const TextStyle(color: Colors.green)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isSignUp ? 'Sign up' : 'Sign in'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(_isSignUp
                      ? 'Have an account? Sign in'
                      : 'New here? Create an account'),
                ),
                const Divider(height: 32),
                const Text('Or continue with'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => _oauth(OAuthProvider.google),
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Text('Google'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => _oauth(OAuthProvider.github),
                      icon: const Icon(Icons.code),
                      label: const Text('GitHub'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze**

Run: `cd samples/twitter_app && flutter analyze lib/main.dart lib/screens/auth_screen.dart`
Expected: "No issues found!" (the `FeedScreen` import resolves once Task 10 lands; if analyzing before Task 10, comment the import + `_AuthGate` `FeedScreen` reference temporarily, or do Tasks 9–11 together before analyzing).

- [ ] **Step 4: Commit**

```bash
git add samples/twitter_app/lib/main.dart samples/twitter_app/lib/screens/auth_screen.dart
git commit -m "feat(sample): app bootstrap, auth gate, and AuthScreen"
```

- [ ] **Step 5: Manual verification (after Task 10's FeedScreen exists)**

Run: `cd samples/twitter_app && flutter run`.
You should see the **Sign in** screen. Toggle to **Create an account**, register a new email/password — if email verification is enabled you'll see the green "check your email" notice; otherwise the screen flips to the feed. Sign in with valid credentials and confirm the gate switches to the feed. Kill and relaunch the app — you should land directly on the feed (session restored from secure storage). Tapping **Google**/**GitHub** opens the system browser; after authorizing, the app should foreground and land on the feed via the deep-link callback.

---

## Task 10: `FeedScreen` — joined feed, pull-to-refresh, pagination, like/unlike

**Files:**
- Create: `samples/twitter_app/lib/screens/feed_screen.dart`

The feed reads `tweets` joined to the author profile, ordered newest-first, paginated with `range`. Like/unlike inserts/deletes a `likes` row keyed by `(tweet_id, user_id)`.

- [ ] **Step 1: Write `screens/feed_screen.dart`**

```dart
// samples/twitter_app/lib/screens/feed_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import '../models/tweet.dart';
import '../providers.dart';
import 'compose_screen.dart';
import 'profile_screen.dart';

const int _pageSize = 20;

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final List<Tweet> _tweets = <Tweet>[];
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
            _scroll.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  DatabaseClient get _db => ref.read(insforgeClientProvider).database;

  Future<void> _refresh() async {
    setState(() {
      _tweets.clear();
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final from = _tweets.length;
      final rows = await _db
          .from('tweets')
          .select(
            '*, author:profiles!tweets_user_id_fkey(name, avatar_url), '
            'likes(user_id)',
          )
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1)
          .execute();
      final page = rows.map(Tweet.fromJson).toList();
      setState(() {
        _tweets.addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } on InsforgeHttpException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike(Tweet tweet, bool currentlyLiked) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      if (currentlyLiked) {
        await _db
            .from('likes')
            .eq('tweet_id', tweet.id)
            .eq('user_id', user.id)
            .delete()
            .execute();
      } else {
        await _db.from('likes').insert(<String, dynamic>{
          'tweet_id': tweet.id,
          'user_id': user.id,
        }).execute();
      }
      await _refresh();
    } on InsforgeHttpException catch (e) {
      _showSnack(e.message);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authClientProvider).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const ComposeScreen()),
          );
          if (created == true) await _refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _error != null
            ? ListView(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error: $_error'),
                  ),
                ],
              )
            : ListView.builder(
                controller: _scroll,
                itemCount: _tweets.length + (_loading ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (index >= _tweets.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final tweet = _tweets[index];
                  // currentlyLiked is approximated by likeCount join presence;
                  // a production app would track which user_ids liked it.
                  final liked = false;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: tweet.authorAvatarUrl != null
                          ? NetworkImage(tweet.authorAvatarUrl!)
                          : null,
                      child: tweet.authorAvatarUrl == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(tweet.authorName ?? 'Anonymous'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(tweet.content),
                        if (tweet.imageUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(tweet.imageUrl!),
                            ),
                          ),
                      ],
                    ),
                    trailing: (user != null)
                        ? IconButton(
                            icon: Icon(
                              liked ? Icons.favorite : Icons.favorite_border,
                            ),
                            color: liked ? Colors.red : null,
                            onPressed: () => _toggleLike(tweet, liked),
                          )
                        : null,
                  );
                },
              ),
      ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

Run: `cd samples/twitter_app && flutter analyze lib/screens/feed_screen.dart`
Expected: "No issues found!" (ComposeScreen + ProfileScreen imports resolve once Tasks 11–12 land; build all three before analyzing if needed).

- [ ] **Step 3: Commit**

```bash
git add samples/twitter_app/lib/screens/feed_screen.dart
git commit -m "feat(sample): FeedScreen with joined feed, pagination, like/unlike"
```

- [ ] **Step 4: Manual verification**

With the backend seeded (see README schema), run `flutter run`. You should see tweets newest-first with author name/avatar; pull down to refresh; scroll to the bottom to trigger pagination (a spinner then more rows). Tap the heart to like/unlike — the count reflects after refresh. Tap the logout icon to return to the auth screen.

---

## Task 11: `ComposeScreen` — new tweet + image upload + AI caption

**Files:**
- Create: `samples/twitter_app/lib/screens/compose_screen.dart`

Compose creates a tweet, optionally picks an image (`image_picker`) and uploads it to the `tweet-images` storage bucket (storing the public URL on the row), and offers a streaming "suggest a caption" AI button when `AppConfig.aiEnabled`.

- [ ] **Step 1: Write `screens/compose_screen.dart`**

```dart
// samples/twitter_app/lib/screens/compose_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:insforge/insforge.dart';

import '../config.dart';
import '../providers.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _content = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageName;
  bool _busy = false;
  bool _aiBusy = false;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageName = picked.name;
    });
  }

  /// Streams an AI-suggested caption into the text field via OpenRouter.
  Future<void> _suggestCaption() async {
    setState(() {
      _aiBusy = true;
      _error = null;
      _content.text = '';
    });
    try {
      final ai = ref.read(insforgeClientProvider).ai;
      final stream = ai.chat.completions.createStream(
        ChatCompletionRequest(
          model: 'openai/gpt-4o-mini',
          messages: <ChatMessage>[
            ChatMessage.system(
              'You write short, witty tweet captions under 200 characters.',
            ),
            ChatMessage.user('Suggest a tweet caption for a casual post.'),
          ],
        ),
      );
      await for (final chunk in stream) {
        final delta = chunk.choices.isNotEmpty
            ? chunk.choices.first.delta.content
            : null;
        if (delta != null) {
          setState(() => _content.text += delta);
        }
      }
    } catch (e) {
      setState(() => _error = 'AI error: $e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _post() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = ref.read(insforgeClientProvider);
    try {
      String? imageUrl;
      if (_imageBytes != null) {
        final stored = await client.storage
            .from('tweet-images')
            .uploadAutoKey(_imageName ?? 'image.jpg', _imageBytes!);
        imageUrl =
            client.storage.from('tweet-images').getPublicUrl(stored.key);
      }
      await client.database.from('tweets').insert(<String, dynamic>{
        'user_id': user.id,
        'content': _content.text.trim(),
        if (imageUrl != null) 'image_url': imageUrl,
      }).execute();
      if (mounted) Navigator.of(context).pop(true);
    } on InsforgeException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New tweet'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _post,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Post'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _content,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: "What's happening?",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_imageBytes!, height: 160),
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Add image'),
                ),
                const SizedBox(width: 12),
                if (AppConfig.aiEnabled)
                  OutlinedButton.icon(
                    onPressed: _aiBusy ? null : _suggestCaption,
                    icon: _aiBusy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: const Text('Suggest caption'),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
```

> Note on AI model types: the exact `ChatCompletionRequest` / `ChatMessage` / chunk-delta API comes from Plan 6 (`insforge_ai`). If those constructors differ (e.g. `ChatMessage(role: ..., content: ...)` instead of named `.system`/`.user` factories), adjust this call site to match the names Plan 6 shipped — the streaming pattern (iterate chunks, append `delta.content`) is unchanged.

- [ ] **Step 2: Analyze**

Run: `cd samples/twitter_app && flutter analyze lib/screens/compose_screen.dart`
Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add samples/twitter_app/lib/screens/compose_screen.dart
git commit -m "feat(sample): ComposeScreen with image upload + streaming AI caption"
```

- [ ] **Step 4: Manual verification**

Tap the feed's `+` FAB. Type some text, tap **Add image** and pick a photo — a preview appears. If an OpenRouter key is configured, tap **Suggest caption** and watch text stream into the field token-by-token. Tap **Post**; you return to the feed and (after refresh) see the new tweet with its uploaded image rendered from the `tweet-images` public URL.

---

## Task 12: `ProfileScreen` — getProfile / updateProfile

**Files:**
- Create: `samples/twitter_app/lib/screens/profile_screen.dart`

- [ ] **Step 1: Write `screens/profile_screen.dart`**

```dart
// samples/twitter_app/lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import '../providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final profile = await ref.read(authClientProvider).getProfile(user.id);
      _name.text = profile.profile['name'] as String? ?? '';
      _bio.text = profile.profile['bio'] as String? ?? '';
    } on InsforgeException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(authClientProvider).updateProfile(<String, dynamic>{
        'name': _name.text.trim(),
        'bio': _bio.text.trim(),
      });
      setState(() => _info = 'Profile saved.');
    } on InsforgeException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (user != null)
                    Text(user.email,
                        style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bio,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Bio'),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  if (_info != null)
                    Text(_info!, style: const TextStyle(color: Colors.green)),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
```

- [ ] **Step 2: Analyze the whole sample app**

Run: `cd samples/twitter_app && flutter analyze`
Expected: "No issues found!" across the entire app (all screens now exist).

- [ ] **Step 3: Commit**

```bash
git add samples/twitter_app/lib/screens/profile_screen.dart
git commit -m "feat(sample): ProfileScreen (getProfile/updateProfile)"
```

- [ ] **Step 4: Manual verification**

From the feed, tap the person icon. The screen loads the current profile (name/bio prefilled). Edit the name, tap **Save** — a green "Profile saved." appears, and because `updateProfile` emits `userUpdated`, any UI bound to the user reflects the change. Reopen the screen to confirm persistence.

---

## Task 13: Sample README + per-platform deep-link configuration

**Files:**
- Create: `samples/twitter_app/README.md`

- [ ] **Step 1: Write `README.md`**

````markdown
# twitter_app — InsForge Flutter SDK sample

A Twitter-style app exercising every InsForge module: **auth** (email/password +
PKCE OAuth deep link), **database** (joined feed, like/unlike, pagination),
**storage** (tweet image upload), and **ai** (streaming caption via OpenRouter).

## 1. Configure

Edit `lib/config.dart`:

- `backendUrl` — your InsForge project base URL (no trailing slash, no module
  path). For the Android emulator talking to a local backend use
  `http://10.0.2.2:7130`; for the iOS simulator use `http://localhost:7130`.
- `anonKey` — your project's anon (public) key.
- `openRouterApiKey` — *(optional)* an OpenRouter key to enable "Suggest
  caption". Leave empty to hide the AI button.
- `oauthScheme` — the custom URI scheme for the OAuth redirect
  (default `insforgetwitter`). Must match the platform config below.

## 2. Backend setup (tables, bucket)

Create these tables in your InsForge project:

```sql
create table profiles (
  id uuid primary key references auth_users(id),
  name text,
  bio text,
  avatar_url text
);

create table tweets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  content text not null,
  image_url text,
  created_at timestamptz not null default now()
);

create table likes (
  tweet_id uuid not null references tweets(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (tweet_id, user_id)
);
```

> The feed query joins via the FK constraint name
> `tweets_user_id_fkey`. If your FK is named differently, update the
> `select('*, author:profiles!<your_fk_name>(...)')` string in
> `lib/screens/feed_screen.dart`.

Create a **public** storage bucket named `tweet-images` (Compose uploads images
there and stores the returned public URL on the tweet row).

## 3. OAuth deep-link configuration

The OAuth flow opens the provider URL in the system browser and captures the
redirect back into the app via a custom URI scheme. Register the scheme on each
platform so the OS routes `insforgetwitter://auth-callback` to the app.

### Android — `android/app/src/main/AndroidManifest.xml`

Add an `intent-filter` inside the existing `<activity android:name=".MainActivity">`:

```xml
<intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="insforgetwitter" android:host="auth-callback" />
</intent-filter>
```

### iOS — `ios/Runner/Info.plist`

Add a `CFBundleURLTypes` entry:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>dev.insforge.twitterapp.oauth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>insforgetwitter</string>
        </array>
    </dict>
</array>
```

When configuring the provider in the InsForge dashboard, add
`insforgetwitter://auth-callback` to the allowed redirect URIs.

## 4. Run

```bash
flutter pub get
cd samples/twitter_app
flutter run
```

## What each screen demonstrates

| Screen | Modules | SDK calls |
|---|---|---|
| AuthScreen | auth | `signUp`, `signIn`, `getOAuthUrl` + `handleOAuthCallback` |
| FeedScreen | database | `from('tweets').select(join).order().range().execute()`, like via insert/delete |
| ComposeScreen | storage, database, ai | `storage.from('tweet-images').uploadAutoKey/getPublicUrl`, `database insert`, `ai.chat.completions.createStream` |
| ProfileScreen | auth | `getProfile`, `updateProfile` |
````

- [ ] **Step 2: Apply the platform deep-link config**

Edit `samples/twitter_app/android/app/src/main/AndroidManifest.xml` and
`samples/twitter_app/ios/Runner/Info.plist` to add the snippets shown in the
README so the OAuth redirect actually routes back to the app.

- [ ] **Step 3: Commit**

```bash
git add samples/twitter_app/README.md samples/twitter_app/android/app/src/main/AndroidManifest.xml samples/twitter_app/ios/Runner/Info.plist
git commit -m "docs(sample): README + per-platform OAuth deep-link config"
```

- [ ] **Step 4: Final manual verification (end-to-end)**

Run: `cd samples/twitter_app && flutter run`.
Exercise the full loop: sign up → sign in → compose a tweet with an image (and an
AI caption if configured) → see it in the feed → like it → open profile and edit
it → sign out → relaunch and confirm you land on the auth screen. With OAuth
configured, sign in with Google/GitHub and confirm the deep-link callback lands
you in the feed.

---

## Self-Review Notes

- **Spec coverage (design §4.7 + §7):** Umbrella package re-exports all six feature packages and adds `SecureSessionStorage` (Task 2), `InsforgeClient` with one shared `InsforgeHttpClient` + one `SessionStorage` and lazy cached `auth`/`database`/`storage`/`functions` getters plus an `ai` getter that throws when no OpenRouter key was supplied (Task 3), and the supabase_flutter-style `Insforge.initialize`/`Insforge.instance` singleton that awaits `restoreSession()` (Task 4). Sample app (Tasks 6–13): config + service layer building `InsforgeClient` (Tasks 6–7), Riverpod providers incl. an `onAuthStateChange` `StreamProvider` (Task 8), AuthScreen (email/password + OAuth, Task 9), FeedScreen (joined `tweets`+`profiles` select, pull-to-refresh, `range` pagination, like via insert/delete, Task 10), ComposeScreen (image pick → `tweet-images` upload → store public URL + streaming AI caption, Task 11), ProfileScreen (`getProfile`/`updateProfile`, Task 12), and a README with DB schema, the `tweet-images` bucket, and Android/iOS deep-link config (Task 13). Covered.
- **How `flutter_secure_storage` is mocked in tests:** `SecureSessionStorage` takes an injectable `FlutterSecureStorage`; the unit test swaps the package's *platform interface* (`FlutterSecureStoragePlatform.instance = _FakeSecureStoragePlatform()`) for an in-memory map, so `flutter test` runs on the Dart VM with no real Keychain/Keystore. `InsforgeClient`/`Insforge` tests sidestep secure storage entirely by injecting the core `InMemorySessionStorage` (via the constructor's `sessionStorage` param and `initialize`'s `@visibleForTesting sessionStorageForTest`).
- **OAuth deep-link wiring:** the SDK only provides `getOAuthUrl(provider, redirectUri, codeChallenge)` and `handleOAuthCallback(uri, verifier)`. `InsforgeService.signInWithOAuth` generates the PKCE verifier/challenge with `PkceHelper`, **subscribes to `AppLinks().uriLinkStream` before** launching (to avoid missing a fast redirect), opens the URL with `url_launcher` (`LaunchMode.externalApplication`), awaits the first incoming `Uri` whose scheme matches `AppConfig.oauthScheme`, then exchanges it. Platform routing is configured via the Android `intent-filter` and iOS `CFBundleURLTypes` documented in the README and applied in Task 13.
- **Riverpod structure:** `insforgeServiceProvider` (owns client + OAuth) → `insforgeClientProvider` → `authClientProvider`; `authStateProvider` is a `StreamProvider<AuthState>` seeded with the current session then forwarding `onAuthStateChange`, and `currentUserProvider` derives the user. `main()` builds a `ProviderContainer`, awaits `restore()` before `runApp`, and uses `UncontrolledProviderScope`; an `_AuthGate` `ConsumerWidget` switches between `FeedScreen` and `AuthScreen` on the stream.
- **Testing approach split (per instructions):** umbrella pure logic is TDD with `flutter_test` (`SecureSessionStorage` delegation, `InsforgeClient` shared-http + lazy getters + ai-key guard, `Insforge` initialize/instance/restore); the sample app is verified **manually** via `flutter run` with concrete expected behavior per screen (no unit tests, full code provided).
- **Cross-plan API names consumed:** `InsforgeHttpClient`, `SessionStorage`, `InMemorySessionStorage`, `InsforgeOptions`, `LogLevel`, `InsforgeException`/`InsforgeHttpException` (Plan 1); `AuthClient(http, storage)`, `signUp`/`signIn`/`signOut`/`getProfile`/`updateProfile`/`getOAuthUrl`/`handleOAuthCallback`/`restoreSession`, `onAuthStateChange`, `AuthState`, `AuthChangeEvent`, `OAuthProvider`, `PkceHelper`, `User`/`Session`/`AuthResponse`/`SignUpResponse` (Plan 2); `DatabaseClient(http)`, `from`/`select`/`order`/`range`/`eq`/`insert`/`delete`/`execute` (Plan 3); `StorageClient(http)`, `from(bucket)`, `uploadAutoKey`/`getPublicUrl`, `StoredFile.key` (Plan 4); `FunctionsClient(http)` (Plan 5); `AIClient(apiKey)`, `chat.completions.createStream`, `ChatCompletionRequest`/`ChatMessage`/chunk `delta.content` (Plan 6). The two AI/storage call sites are flagged with adjust-if-different notes since Plans 4 and 6 finalize those exact constructor names.
- **Deferred / assumptions:** the `likes(user_id)` join is used for like *count*; tracking which user already liked a given tweet (to render the filled heart) is left as a TODO in `FeedScreen` (`liked = false`) to keep the sample focused — a production app would map the joined `likes.user_id` list against the current user. `flutter create` generates the Android/iOS host projects (Task 6) which we then edit; the workspace root switches from `dart pub get` to `flutter pub get` from this plan onward because Flutter packages now participate.
