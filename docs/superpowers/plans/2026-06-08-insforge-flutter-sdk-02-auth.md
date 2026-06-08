# InsForge Flutter SDK — Plan 2: `insforge_auth` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart `insforge_auth` package on top of `insforge_core`: email/password auth, PKCE OAuth, email verification + password reset flows, profile read/update, hand-written model (de)serialization, JWT-`exp` decoding, session persistence via `SessionStorage`, a broadcast `onAuthStateChange` stream, proactive + reactive token refresh, and registration of the `InsforgeHttpClient` refresh callback.

**Architecture:** `AuthClient` wraps the shared `InsforgeHttpClient` (Plan 1) and a `SessionStorage`. It is the *writer* of the http client's `accessToken` and the *registrar* of its `RefreshCallback`; the http client is the reader. Token-issuing calls (signup / signin / refresh / verify / oauth-exchange) append `client_type=mobile` so a `refreshToken` is returned in the body (Flutter has no cookie jar). On every successful auth result `AuthClient` stores `insforge_refresh_token` / `insforge_access_token` / `insforge_user` via `SessionStorage`, sets `http.accessToken`, updates in-memory `currentSession`/`currentUser`, and emits an `AuthState` on the broadcast stream. `restoreSession()` rehydrates from storage and proactively refreshes when the JWT `exp` is within a leeway window. No Flutter dependency.

**Tech Stack:** Dart ≥ 3.5 (pub workspaces), `dio` ^5.7.0, `crypto` ^3.0.5 (SHA-256 for PKCE), `meta` ^1.15.0, `insforge_core` (path), `test`, `http_mock_adapter`, `lints`.

**Prerequisite:** The Flutter SDK (which bundles Dart) must be installed and on `PATH` (`dart --version` must work). Plan 1 (`insforge_core`) must be complete and committed — this package depends on it via a path/workspace dependency.

**Plan series:** This is plan 2 of 7. Plan 1 (workspace + `insforge_core`) precedes it; subsequent plans: 03 database, 04 storage, 05 functions, 06 ai, 07 umbrella + sample. Each later package adds itself to the workspace member list created in Plan 1.

---

## File Structure

```
insforge-flutter/
├── pubspec.yaml                              # MODIFIED: append packages/insforge_auth to workspace
└── packages/
    └── insforge_auth/
        ├── pubspec.yaml
        ├── analysis_options.yaml             # includes root lints
        ├── lib/
        │   ├── insforge_auth.dart            # public exports
        │   └── src/
        │       ├── enums.dart                # OAuthProvider, ClientType, AuthChangeEvent
        │       ├── models/
        │       │   ├── user.dart             # User (+ name/avatarUrl getters)
        │       │   ├── session.dart          # Session
        │       │   ├── auth_response.dart     # AuthResponse
        │       │   ├── sign_up_response.dart  # SignUpResponse (+ hasSession)
        │       │   ├── profile.dart          # Profile
        │       │   └── reset_token_response.dart  # ResetTokenResponse
        │       ├── auth_state.dart           # AuthState
        │       ├── auth_options.dart         # AuthOptions
        │       ├── pkce.dart                 # PkceHelper
        │       ├── jwt.dart                  # decodeJwtExpiry
        │       └── auth_client.dart          # AuthClient
        └── test/
            ├── pkce_test.dart
            ├── jwt_test.dart
            ├── user_test.dart
            ├── auth_response_test.dart
            ├── sign_up_response_test.dart
            ├── profile_test.dart
            ├── enums_test.dart
            ├── auth_client_sign_in_test.dart
            ├── auth_client_sign_up_test.dart
            ├── auth_client_sign_out_test.dart
            ├── auth_client_refresh_test.dart
            ├── auth_client_oauth_test.dart
            ├── auth_client_profile_test.dart
            ├── auth_client_restore_test.dart
            └── auth_client_refresh_callback_test.dart
```

---

## Task 1: Package scaffolding + workspace registration

**Files:**
- Create: `packages/insforge_auth/pubspec.yaml`
- Create: `packages/insforge_auth/analysis_options.yaml`
- Create: `packages/insforge_auth/lib/insforge_auth.dart`
- Modify: `pubspec.yaml` (workspace root)

- [ ] **Step 1: Create the package `pubspec.yaml`**

```yaml
# packages/insforge_auth/pubspec.yaml
name: insforge_auth
description: Authentication for the InsForge Flutter SDK — email/password, PKCE OAuth, sessions, and profiles.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.5.0

dependencies:
  dio: ^5.7.0
  meta: ^1.15.0
  crypto: ^3.0.5
  insforge_core:
    path: ../insforge_core

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  http_mock_adapter: ^0.6.1
```

- [ ] **Step 2: Create the package-local `analysis_options.yaml`**

```yaml
# packages/insforge_auth/analysis_options.yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 3: Create a placeholder library export file**

```dart
// packages/insforge_auth/lib/insforge_auth.dart
/// Authentication for the InsForge Flutter SDK.
library insforge_auth;

// Exports are added as each component lands in later tasks.
```

- [ ] **Step 4: Register the package in the workspace root `pubspec.yaml`**

In the repo-root `pubspec.yaml` created by Plan 1, the `workspace:` list currently reads:

```yaml
workspace:
  - packages/insforge_core
```

Replace it with:

```yaml
workspace:
  - packages/insforge_core
  - packages/insforge_auth
```

- [ ] **Step 5: Resolve dependencies**

Run: `dart pub get` (from repo root)
Expected: resolves the workspace including `insforge_auth`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/insforge_auth/pubspec.yaml packages/insforge_auth/analysis_options.yaml packages/insforge_auth/lib/insforge_auth.dart
git commit -m "feat(auth): add insforge_auth package skeleton"
```

---

## Task 2: Enums — `OAuthProvider`, `ClientType`, `AuthChangeEvent`

**Files:**
- Create: `packages/insforge_auth/lib/src/enums.dart`
- Test: `packages/insforge_auth/test/enums_test.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/enums_test.dart`
Expected: FAIL — `OAuthProvider`/`ClientType`/`AuthChangeEvent` not defined.

- [ ] **Step 3: Write `enums.dart`**

```dart
// packages/insforge_auth/lib/src/enums.dart

/// OAuth providers supported by the InsForge backend.
///
/// [wireName] is the value used in the `/api/auth/oauth/{provider}` path.
enum OAuthProvider {
  google('google'),
  github('github'),
  discord('discord'),
  linkedin('linkedin'),
  facebook('facebook'),
  instagram('instagram'),
  tiktok('tiktok'),
  apple('apple'),
  x('x'),
  spotify('spotify'),
  microsoft('microsoft');

  const OAuthProvider(this.wireName);

  /// The provider key sent on the wire (e.g. `google`).
  final String wireName;
}

/// Client type sent as the `client_type` query parameter on token-issuing
/// calls. Mobile/desktop/server return the refresh token in the body; web
/// uses an httpOnly cookie. The Flutter SDK defaults to [ClientType.mobile].
enum ClientType {
  web('web'),
  mobile('mobile'),
  desktop('desktop'),
  server('server');

  const ClientType(this.wireName);

  /// The value sent in the `client_type` query parameter.
  final String wireName;
}

/// Lifecycle events emitted on [AuthClient.onAuthStateChange].
enum AuthChangeEvent {
  /// A new session was established (sign-up with session, sign-in, verify,
  /// or OAuth exchange).
  signedIn,

  /// The session was cleared.
  signedOut,

  /// The access token was refreshed; the session is otherwise unchanged.
  tokenRefreshed,

  /// The current user's profile/details changed (e.g. `updateProfile`).
  userUpdated,
}
```

- [ ] **Step 4: Export it**

In `packages/insforge_auth/lib/insforge_auth.dart`, replace the trailing comment with:

```dart
export 'src/enums.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/enums_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_auth/lib/src/enums.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/enums_test.dart
git commit -m "feat(auth): add OAuthProvider, ClientType, AuthChangeEvent enums"
```

---

## Task 3: PKCE helper

**Files:**
- Create: `packages/insforge_auth/lib/src/pkce.dart`
- Test: `packages/insforge_auth/test/pkce_test.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

The known-answer vector below is from RFC 7636 Appendix B:
`code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"` →
`code_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/pkce_test.dart
import 'package:insforge_auth/insforge_auth.dart';
import 'package:test/test.dart';

void main() {
  group('PkceHelper', () {
    test('generateCodeVerifier produces a 43-128 char base64url string', () {
      final verifier = PkceHelper.generateCodeVerifier();
      expect(verifier.length, greaterThanOrEqualTo(43));
      expect(verifier.length, lessThanOrEqualTo(128));
      // base64url alphabet only (no padding, no + or /).
      expect(RegExp(r'^[A-Za-z0-9\-_]+$').hasMatch(verifier), isTrue);
    });

    test('generateCodeVerifier returns distinct values', () {
      final a = PkceHelper.generateCodeVerifier();
      final b = PkceHelper.generateCodeVerifier();
      expect(a, isNot(equals(b)));
    });

    test('codeChallenge matches the RFC 7636 Appendix B vector', () {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final challenge = PkceHelper.codeChallenge(verifier);
      expect(challenge, 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('codeChallenge output is base64url without padding', () {
      final challenge =
          PkceHelper.codeChallenge(PkceHelper.generateCodeVerifier());
      expect(challenge.contains('='), isFalse);
      expect(challenge.contains('+'), isFalse);
      expect(challenge.contains('/'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/pkce_test.dart`
Expected: FAIL — `PkceHelper` not defined.

- [ ] **Step 3: Write `pkce.dart`**

```dart
// packages/insforge_auth/lib/src/pkce.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636) helper for OAuth 2.0 authorization-code flows.
///
/// The verifier is a cryptographically random base64url string (43-128 chars);
/// the challenge is `BASE64URL(SHA256(ASCII(verifier)))` without padding.
class PkceHelper {
  PkceHelper._();

  static final Random _random = Random.secure();

  /// Generates a random code verifier.
  ///
  /// 32 random bytes base64url-encode to a 43-character string, which is the
  /// RFC-mandated minimum length and within the 43-128 range.
  static String generateCodeVerifier() {
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return _base64UrlNoPad(bytes);
  }

  /// Derives the code challenge from [verifier]:
  /// `BASE64URL(SHA256(ASCII(verifier)))` with padding stripped.
  static String codeChallenge(String verifier) {
    final digest = sha256.convert(ascii.encode(verifier));
    return _base64UrlNoPad(Uint8List.fromList(digest.bytes));
  }

  static String _base64UrlNoPad(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/pkce.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/pkce_test.dart`
Expected: All tests PASS (including the RFC vector).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_auth/lib/src/pkce.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/pkce_test.dart
git commit -m "feat(auth): add PKCE helper (verifier + S256 challenge)"
```

---

## Task 4: JWT `exp` decoder

**Files:**
- Create: `packages/insforge_auth/lib/src/jwt.dart`
- Test: `packages/insforge_auth/test/jwt_test.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/jwt_test.dart
import 'dart:convert';

import 'package:insforge_auth/insforge_auth.dart';
import 'package:test/test.dart';

/// Builds an unsigned-but-structurally-valid JWT carrying the given payload.
String _makeJwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'});
  final body = seg(payload);
  return '$header.$body.signature';
}

void main() {
  group('decodeJwtExpiry', () {
    test('reads the exp claim (seconds) as a UTC DateTime', () {
      // 2026-06-08T10:30:00Z = 1781260200 seconds since epoch.
      const expSeconds = 1781260200;
      final token = _makeJwt(<String, dynamic>{'sub': 'u1', 'exp': expSeconds});

      final result = decodeJwtExpiry(token);

      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.millisecondsSinceEpoch, expSeconds * 1000);
    });

    test('returns null when exp is absent', () {
      final token = _makeJwt(<String, dynamic>{'sub': 'u1'});
      expect(decodeJwtExpiry(token), isNull);
    });

    test('returns null for a malformed token', () {
      expect(decodeJwtExpiry('not.a.jwt.at.all'), isNull);
      expect(decodeJwtExpiry('onlyonesegment'), isNull);
      expect(decodeJwtExpiry(''), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/jwt_test.dart`
Expected: FAIL — `decodeJwtExpiry` not defined.

- [ ] **Step 3: Write `jwt.dart`**

```dart
// packages/insforge_auth/lib/src/jwt.dart
import 'dart:convert';

/// Decodes the `exp` (expiry) claim of a JWT without verifying the signature.
///
/// Returns the expiry as a UTC [DateTime], or null when the token is malformed
/// or carries no numeric `exp` claim. Used only for proactive-refresh timing —
/// never for authorization decisions.
DateTime? decodeJwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final payloadJson = utf8.decode(base64Url.decode(normalized));
    final payload = jsonDecode(payloadJson);
    if (payload is! Map<String, dynamic>) return null;
    final exp = payload['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (exp * 1000).toInt(),
      isUtc: true,
    );
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/jwt.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/jwt_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_auth/lib/src/jwt.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/jwt_test.dart
git commit -m "feat(auth): add JWT exp decoder for proactive refresh"
```

---

## Task 5: `User` model

**Files:**
- Create: `packages/insforge_auth/lib/src/models/user.dart`
- Test: `packages/insforge_auth/test/user_test.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

Per `auth.yaml` `UserResponse`: `id`, `email`, `emailVerified` (bool), `providers`
(string array), `profile` (nullable object), `metadata` (nullable object),
`createdAt`/`updatedAt` (date-time). `name`/`avatarUrl` read `profile['name']` /
`profile['avatar_url']`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/user_test.dart`
Expected: FAIL — `User` not defined.

- [ ] **Step 3: Write `user.dart`**

```dart
// packages/insforge_auth/lib/src/models/user.dart
import 'package:insforge_core/insforge_core.dart';

/// An authenticated InsForge user (mirrors `UserResponse` in auth.yaml).
class User {
  const User({
    required this.id,
    required this.email,
    this.emailVerified = false,
    this.providers = const <String>[],
    this.profile,
    this.metadata,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String email;
  final bool emailVerified;
  final List<String> providers;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Display name read from `profile['name']`, if present.
  String? get name => profile?['name'] as String?;

  /// Avatar URL read from `profile['avatar_url']`, if present.
  String? get avatarUrl => profile?['avatar_url'] as String?;

  factory User.fromJson(Map<String, dynamic> json) {
    final rawProviders = json['providers'];
    final rawProfile = json['profile'];
    final rawMetadata = json['metadata'];
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      emailVerified: json['emailVerified'] as bool? ?? false,
      providers: rawProviders is List
          ? rawProviders.map((dynamic e) => e.toString()).toList()
          : const <String>[],
      profile:
          rawProfile is Map ? Map<String, dynamic>.from(rawProfile) : null,
      metadata:
          rawMetadata is Map ? Map<String, dynamic>.from(rawMetadata) : null,
      createdAt: parseInsforgeDate(json['createdAt'] as String?),
      updatedAt: parseInsforgeDate(json['updatedAt'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      'emailVerified': emailVerified,
      'providers': providers,
      if (profile != null) 'profile': profile,
      if (metadata != null) 'metadata': metadata,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/models/user.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/user_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_auth/lib/src/models/user.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/user_test.dart
git commit -m "feat(auth): add User model with hand-written (de)serialization"
```

---

## Task 6: `Session` model

**Files:**
- Create: `packages/insforge_auth/lib/src/models/session.dart`
- Test: covered indirectly by `auth_response_test.dart` (Task 7) and the client
  tests; a dedicated round-trip test is included below.
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/session_test.dart
import 'package:insforge_auth/insforge_auth.dart';
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/session_test.dart`
Expected: FAIL — `Session` not defined.

- [ ] **Step 3: Write `session.dart`**

```dart
// packages/insforge_auth/lib/src/models/session.dart
import 'user.dart';

/// A signed-in session: the access token (+ optional refresh token) and the
/// associated [User].
class Session {
  const Session({
    required this.accessToken,
    required this.user,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;
  final User user;

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      user: User.fromJson(
        Map<String, dynamic>.from(json['user'] as Map),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'accessToken': accessToken,
      if (refreshToken != null) 'refreshToken': refreshToken,
      'user': user.toJson(),
    };
  }

  Session copyWith({String? accessToken, String? refreshToken, User? user}) {
    return Session(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      user: user ?? this.user,
    );
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/models/session.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/session_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_auth/lib/src/models/session.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/session_test.dart
git commit -m "feat(auth): add Session model"
```

---

## Task 7: `AuthResponse` model

**Files:**
- Create: `packages/insforge_auth/lib/src/models/auth_response.dart`
- Test: `packages/insforge_auth/test/auth_response_test.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

`AuthResponse` is the common shape returned by signin, verify, refresh, and
oauth-exchange: `{user, accessToken, refreshToken?}`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_response_test.dart`
Expected: FAIL — `AuthResponse` not defined.

- [ ] **Step 3: Write `auth_response.dart`**

```dart
// packages/insforge_auth/lib/src/models/auth_response.dart
import 'session.dart';
import 'user.dart';

/// Response from a token-issuing call (signin, verify-email, refresh, oauth
/// exchange): the user plus an access token and optional refresh token.
class AuthResponse {
  const AuthResponse({
    required this.user,
    required this.accessToken,
    this.refreshToken,
  });

  final User user;
  final String accessToken;
  final String? refreshToken;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: User.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
    );
  }

  /// Builds a [Session] from this response.
  Session toSession() => Session(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      );
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/models/auth_response.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_response_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_auth/lib/src/models/auth_response.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/auth_response_test.dart
git commit -m "feat(auth): add AuthResponse model"
```

---

## Task 8: `SignUpResponse` model

**Files:**
- Create: `packages/insforge_auth/lib/src/models/sign_up_response.dart`
- Test: `packages/insforge_auth/test/sign_up_response_test.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

Per `auth.yaml` `POST /api/auth/users`: `{user, accessToken?, refreshToken?,
requireEmailVerification}` — `accessToken`/`refreshToken` are null when email
verification is required. `hasSession` is true when an `accessToken` is present.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/sign_up_response_test.dart
import 'package:insforge_auth/insforge_auth.dart';
import 'package:test/test.dart';

void main() {
  group('SignUpResponse.fromJson', () {
    test('immediate-session signup (verification disabled)', () {
      final r = SignUpResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u', 'email': 'e@e.com'},
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'requireEmailVerification': false,
      });
      expect(r.accessToken, 'access-1');
      expect(r.refreshToken, 'refresh-1');
      expect(r.requireEmailVerification, isFalse);
      expect(r.hasSession, isTrue);
    });

    test('verification-required signup has no tokens and no session', () {
      final r = SignUpResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u2', 'email': 'e2@e.com'},
        'accessToken': null,
        'refreshToken': null,
        'requireEmailVerification': true,
      });
      expect(r.accessToken, isNull);
      expect(r.refreshToken, isNull);
      expect(r.requireEmailVerification, isTrue);
      expect(r.hasSession, isFalse);
    });

    test('requireEmailVerification defaults to false when absent', () {
      final r = SignUpResponse.fromJson(<String, dynamic>{
        'user': <String, dynamic>{'id': 'u3', 'email': 'e3@e.com'},
        'accessToken': 'a',
      });
      expect(r.requireEmailVerification, isFalse);
      expect(r.hasSession, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/sign_up_response_test.dart`
Expected: FAIL — `SignUpResponse` not defined.

- [ ] **Step 3: Write `sign_up_response.dart`**

```dart
// packages/insforge_auth/lib/src/models/sign_up_response.dart
import 'session.dart';
import 'user.dart';

/// Response from `POST /api/auth/users`.
///
/// When email verification is required, [accessToken] and [refreshToken] are
/// null and [requireEmailVerification] is true; the caller must complete the
/// verification flow before a session exists.
class SignUpResponse {
  const SignUpResponse({
    required this.user,
    this.accessToken,
    this.refreshToken,
    this.requireEmailVerification = false,
  });

  final User user;
  final String? accessToken;
  final String? refreshToken;
  final bool requireEmailVerification;

  /// True when the signup yielded an immediate session (an access token).
  bool get hasSession => accessToken != null;

  factory SignUpResponse.fromJson(Map<String, dynamic> json) {
    return SignUpResponse(
      user: User.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      requireEmailVerification:
          json['requireEmailVerification'] as bool? ?? false,
    );
  }

  /// Builds a [Session] when this response carries an access token, else null.
  Session? toSession() {
    final token = accessToken;
    if (token == null) return null;
    return Session(
      accessToken: token,
      refreshToken: refreshToken,
      user: user,
    );
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/models/sign_up_response.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/sign_up_response_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_auth/lib/src/models/sign_up_response.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/sign_up_response_test.dart
git commit -m "feat(auth): add SignUpResponse model"
```

---

## Task 9: `Profile` + `ResetTokenResponse` models

**Files:**
- Create: `packages/insforge_auth/lib/src/models/profile.dart`
- Create: `packages/insforge_auth/lib/src/models/reset_token_response.dart`
- Test: `packages/insforge_auth/test/profile_test.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

Per `auth.yaml` `ProfileResponse`: `{id, profile}`. Per
`exchange-reset-password-token`: `{token, expiresAt}`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/profile_test.dart
import 'package:insforge_auth/insforge_auth.dart';
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/profile_test.dart`
Expected: FAIL — `Profile`/`ResetTokenResponse` not defined.

- [ ] **Step 3: Write `profile.dart`**

```dart
// packages/insforge_auth/lib/src/models/profile.dart

/// A user's public profile (mirrors `ProfileResponse` in auth.yaml).
class Profile {
  const Profile({required this.id, required this.profile});

  final String id;
  final Map<String, dynamic> profile;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final raw = json['profile'];
    return Profile(
      id: json['id'] as String,
      profile:
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'id': id, 'profile': profile};
  }
}
```

- [ ] **Step 4: Write `reset_token_response.dart`**

```dart
// packages/insforge_auth/lib/src/models/reset_token_response.dart
import 'package:insforge_core/insforge_core.dart';

/// Response from `POST /api/auth/email/exchange-reset-password-token`:
/// a short-lived reset token usable with `resetPassword`.
class ResetTokenResponse {
  const ResetTokenResponse({required this.token, this.expiresAt});

  final String token;
  final DateTime? expiresAt;

  factory ResetTokenResponse.fromJson(Map<String, dynamic> json) {
    return ResetTokenResponse(
      token: json['token'] as String,
      expiresAt: parseInsforgeDate(json['expiresAt'] as String?),
    );
  }
}
```

- [ ] **Step 5: Export them**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/models/profile.dart';
export 'src/models/reset_token_response.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/profile_test.dart`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/insforge_auth/lib/src/models/profile.dart packages/insforge_auth/lib/src/models/reset_token_response.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/profile_test.dart
git commit -m "feat(auth): add Profile and ResetTokenResponse models"
```

---

## Task 10: `AuthState` + `AuthOptions`

**Files:**
- Create: `packages/insforge_auth/lib/src/auth_state.dart`
- Create: `packages/insforge_auth/lib/src/auth_options.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

These are plain value types exercised by the client tests (Tasks 11+). No
dedicated test file.

- [ ] **Step 1: Write `auth_state.dart`**

```dart
// packages/insforge_auth/lib/src/auth_state.dart
import 'enums.dart';
import 'models/session.dart';

/// Emitted on [AuthClient.onAuthStateChange]. Carries the lifecycle [event]
/// and the current [session] (null after sign-out).
class AuthState {
  const AuthState(this.event, this.session);

  final AuthChangeEvent event;
  final Session? session;
}
```

- [ ] **Step 2: Write `auth_options.dart`**

```dart
// packages/insforge_auth/lib/src/auth_options.dart
import 'enums.dart';

/// Tunable behavior for [AuthClient].
class AuthOptions {
  const AuthOptions({
    this.autoRefreshToken = true,
    this.clientType = ClientType.mobile,
  });

  /// When true, the client registers a refresh callback with the HTTP client
  /// (reactive 401 refresh) and proactively refreshes near token expiry.
  final bool autoRefreshToken;

  /// Client type sent as `client_type` on token-issuing calls. Defaults to
  /// [ClientType.mobile] so refresh tokens are returned in the body.
  final ClientType clientType;
}
```

- [ ] **Step 3: Export them**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/auth_state.dart';
export 'src/auth_options.dart';
```

- [ ] **Step 4: Analyze**

Run: `cd packages/insforge_auth && dart analyze`
Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_state.dart packages/insforge_auth/lib/src/auth_options.dart packages/insforge_auth/lib/insforge_auth.dart
git commit -m "feat(auth): add AuthState and AuthOptions value types"
```

---

## Task 11: `AuthClient` — construction, storage keys, sign-in + persistence

**Files:**
- Create: `packages/insforge_auth/lib/src/auth_client.dart`
- Test: `packages/insforge_auth/test/auth_client_sign_in_test.dart`
- Modify: `packages/insforge_auth/lib/insforge_auth.dart`

This task lands the core `AuthClient` plus `signIn`. Later tasks add the
remaining methods to the same file.

The testing recipe constructs a real `InsforgeHttpClient` and stubs its `dio`
via `http_mock_adapter`'s `DioAdapter`. Token-issuing calls append
`client_type=mobile`, so the matcher asserts that query parameter.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_sign_in_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('signIn parses the response, persists, and emits signedIn', () async {
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{
          'id': 'u-1',
          'email': 'a@b.com',
          'emailVerified': true,
        },
        'accessToken': 'access-token-1',
        'refreshToken': 'refresh-token-1',
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final states = <AuthState>[];
    final sub = auth.onAuthStateChange.listen(states.add);

    final response = await auth.signIn(email: 'a@b.com', password: 'pw');

    expect(response.accessToken, 'access-token-1');
    expect(response.user.id, 'u-1');

    // HTTP client now carries the new access token.
    expect(http.accessToken, 'access-token-1');

    // Session persisted under the documented keys.
    expect(await storage.read('insforge_access_token'), 'access-token-1');
    expect(await storage.read('insforge_refresh_token'), 'refresh-token-1');
    expect(await storage.read('insforge_user'), isNotNull);

    // In-memory state updated.
    expect(auth.currentUser?.id, 'u-1');
    expect(auth.currentSession?.accessToken, 'access-token-1');

    // Auth state emitted.
    await Future<void>.delayed(Duration.zero);
    expect(states.single.event, AuthChangeEvent.signedIn);
    expect(states.single.session?.accessToken, 'access-token-1');

    await sub.cancel();
  });

  test('signIn throws InsforgeHttpException on 401', () async {
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(401, <String, dynamic>{
        'error': 'AUTH_INVALID_CREDENTIALS',
        'message': 'Invalid email or password',
        'statusCode': 401,
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    expect(
      () => auth.signIn(email: 'a@b.com', password: 'bad'),
      throwsA(isA<InsforgeHttpException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_client_sign_in_test.dart`
Expected: FAIL — `AuthClient` not defined.

- [ ] **Step 3: Write `auth_client.dart` (core + signIn)**

```dart
// packages/insforge_auth/lib/src/auth_client.dart
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';

import 'auth_options.dart';
import 'auth_state.dart';
import 'enums.dart';
import 'jwt.dart';
import 'models/auth_response.dart';
import 'models/profile.dart';
import 'models/reset_token_response.dart';
import 'models/session.dart';
import 'models/sign_up_response.dart';
import 'models/user.dart';
import 'pkce.dart';

/// Storage key for the persisted refresh token.
const String kRefreshTokenKey = 'insforge_refresh_token';

/// Storage key for the persisted access token.
const String kAccessTokenKey = 'insforge_access_token';

/// Storage key for the persisted serialized [User].
const String kUserKey = 'insforge_user';

/// Refresh proactively when the access token expires within this leeway.
const Duration kProactiveRefreshLeeway = Duration(seconds: 30);

/// High-level authentication client.
///
/// Wraps a shared [InsforgeHttpClient] and a [SessionStorage]. Writes the
/// http client's access token, registers its refresh callback, persists the
/// session, and broadcasts [AuthState] changes.
class AuthClient {
  AuthClient(
    this._http,
    this._storage, {
    AuthOptions? options,
  }) : _options = options ?? const AuthOptions() {
    if (_options.autoRefreshToken) {
      _http.registerRefreshCallback(_refreshForHttpClient);
    }
  }

  final InsforgeHttpClient _http;
  final SessionStorage _storage;
  final AuthOptions _options;

  final StreamController<AuthState> _stateController =
      StreamController<AuthState>.broadcast();

  Session? _currentSession;

  /// Broadcast stream of authentication lifecycle changes.
  Stream<AuthState> get onAuthStateChange => _stateController.stream;

  /// The currently signed-in user, or null.
  User? get currentUser => _currentSession?.user;

  /// The current session, or null when signed out.
  Session? get currentSession => _currentSession;

  /// The `client_type` query parameter applied to token-issuing calls.
  Map<String, dynamic> get _clientTypeQuery =>
      <String, dynamic>{'client_type': _options.clientType.wireName};

  // ---------------------------------------------------------------------------
  // Email / password
  // ---------------------------------------------------------------------------

  /// Signs in with email + password. Persists and emits on success.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/sessions',
      data: <String, dynamic>{'email': email, 'password': password},
      queryParameters: _clientTypeQuery,
    );
    final response = AuthResponse.fromJson(res.data!);
    await _applySession(response.toSession(), AuthChangeEvent.signedIn);
    return response;
  }

  // ---------------------------------------------------------------------------
  // Session application + persistence (shared by all auth flows)
  // ---------------------------------------------------------------------------

  Future<void> _applySession(Session session, AuthChangeEvent event) async {
    _currentSession = session;
    _http.accessToken = session.accessToken;
    await _persist(session);
    _stateController.add(AuthState(event, session));
  }

  Future<void> _persist(Session session) async {
    await _storage.write(kAccessTokenKey, session.accessToken);
    final refresh = session.refreshToken;
    if (refresh != null) {
      await _storage.write(kRefreshTokenKey, refresh);
    }
    await _storage.write(kUserKey, jsonEncode(session.user.toJson()));
  }

  Future<void> _clearPersisted() async {
    await _storage.delete(kAccessTokenKey);
    await _storage.delete(kRefreshTokenKey);
    await _storage.delete(kUserKey);
  }

  // ---------------------------------------------------------------------------
  // Refresh callback for the HTTP client (reactive 401 refresh)
  // ---------------------------------------------------------------------------

  Future<String> _refreshForHttpClient() async {
    final response = await refreshAccessToken();
    return response.accessToken;
  }

  /// Refreshes the access token using the persisted refresh token.
  /// Implemented in Task 14.
  Future<AuthResponse> refreshAccessToken() {
    throw UnimplementedError('refreshAccessToken is implemented in Task 14');
  }

  /// Releases the broadcast stream controller.
  Future<void> dispose() => _stateController.close();
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_auth/lib/insforge_auth.dart`:

```dart
export 'src/auth_client.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_sign_in_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_client.dart packages/insforge_auth/lib/insforge_auth.dart packages/insforge_auth/test/auth_client_sign_in_test.dart
git commit -m "feat(auth): add AuthClient core + signIn with persistence"
```

---

## Task 12: `AuthClient.signUp`

**Files:**
- Modify: `packages/insforge_auth/lib/src/auth_client.dart`
- Test: `packages/insforge_auth/test/auth_client_sign_up_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_sign_up_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('signUp with immediate session persists and emits signedIn', () async {
    adapter.onPost(
      '/api/auth/users',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-1', 'email': 'a@b.com'},
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'requireEmailVerification': false,
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final states = <AuthState>[];
    final sub = auth.onAuthStateChange.listen(states.add);

    final result =
        await auth.signUp(email: 'a@b.com', password: 'pw', name: 'Ada');

    expect(result.hasSession, isTrue);
    expect(result.requireEmailVerification, isFalse);
    expect(http.accessToken, 'access-1');
    expect(await storage.read('insforge_access_token'), 'access-1');

    await Future<void>.delayed(Duration.zero);
    expect(states.single.event, AuthChangeEvent.signedIn);
    await sub.cancel();
  });

  test('signUp requiring verification does not persist or emit', () async {
    adapter.onPost(
      '/api/auth/users',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-2', 'email': 'c@d.com'},
        'accessToken': null,
        'refreshToken': null,
        'requireEmailVerification': true,
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final states = <AuthState>[];
    final sub = auth.onAuthStateChange.listen(states.add);

    final result = await auth.signUp(email: 'c@d.com', password: 'pw');

    expect(result.hasSession, isFalse);
    expect(result.requireEmailVerification, isTrue);
    expect(http.accessToken, isNull);
    expect(await storage.read('insforge_access_token'), isNull);

    await Future<void>.delayed(Duration.zero);
    expect(states, isEmpty);
    await sub.cancel();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_client_sign_up_test.dart`
Expected: FAIL — `signUp` not defined.

- [ ] **Step 3: Add `signUp` to `auth_client.dart`**

Insert this method directly after the `signIn` method (before the
`// Session application` comment block):

```dart
  /// Registers a new user. When email verification is disabled the response
  /// carries a session, which is persisted and emitted; otherwise no session
  /// is established yet.
  Future<SignUpResponse> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/users',
      data: <String, dynamic>{
        'email': email,
        'password': password,
        if (name != null) 'name': name,
      },
      queryParameters: _clientTypeQuery,
    );
    final response = SignUpResponse.fromJson(res.data!);
    final session = response.toSession();
    if (session != null) {
      await _applySession(session, AuthChangeEvent.signedIn);
    }
    return response;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_sign_up_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_client.dart packages/insforge_auth/test/auth_client_sign_up_test.dart
git commit -m "feat(auth): add AuthClient.signUp"
```

---

## Task 13: `AuthClient.signOut`

**Files:**
- Modify: `packages/insforge_auth/lib/src/auth_client.dart`
- Test: `packages/insforge_auth/test/auth_client_sign_out_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_sign_out_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('signOut clears state, storage, and emits signedOut', () async {
    // First sign in.
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-1', 'email': 'a@b.com'},
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );
    adapter.onPost(
      '/api/auth/logout',
      (server) => server.reply(200, <String, dynamic>{'success': true}),
      data: Matchers.any,
    );

    await auth.signIn(email: 'a@b.com', password: 'pw');
    expect(auth.currentSession, isNotNull);

    final states = <AuthState>[];
    final sub = auth.onAuthStateChange.listen(states.add);

    await auth.signOut();

    expect(auth.currentSession, isNull);
    expect(auth.currentUser, isNull);
    expect(http.accessToken, isNull);
    expect(await storage.read('insforge_access_token'), isNull);
    expect(await storage.read('insforge_refresh_token'), isNull);
    expect(await storage.read('insforge_user'), isNull);

    await Future<void>.delayed(Duration.zero);
    expect(states.single.event, AuthChangeEvent.signedOut);
    expect(states.single.session, isNull);
    await sub.cancel();
  });

  test('signOut still clears local state if the logout request fails',
      () async {
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-1', 'email': 'a@b.com'},
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );
    adapter.onPost(
      '/api/auth/logout',
      (server) => server.reply(500, <String, dynamic>{
        'error': 'SERVER_ERROR',
        'message': 'boom',
        'statusCode': 500,
      }),
      data: Matchers.any,
    );

    await auth.signIn(email: 'a@b.com', password: 'pw');
    await auth.signOut();

    expect(auth.currentSession, isNull);
    expect(http.accessToken, isNull);
    expect(await storage.read('insforge_access_token'), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_client_sign_out_test.dart`
Expected: FAIL — `signOut` not defined.

- [ ] **Step 3: Add `signOut` to `auth_client.dart`**

Insert this method after `signUp`:

```dart
  /// Signs out: best-effort backend logout, then clears in-memory and
  /// persisted session and emits [AuthChangeEvent.signedOut].
  Future<void> signOut() async {
    try {
      await _http.request<dynamic>('POST', '/api/auth/logout');
    } catch (_) {
      // Ignore backend logout failures; local state is cleared regardless.
    }
    _currentSession = null;
    _http.accessToken = null;
    await _clearPersisted();
    _stateController.add(const AuthState(AuthChangeEvent.signedOut, null));
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_sign_out_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_client.dart packages/insforge_auth/test/auth_client_sign_out_test.dart
git commit -m "feat(auth): add AuthClient.signOut"
```

---

## Task 14: `AuthClient.refreshAccessToken` + `getCurrentUser`

**Files:**
- Modify: `packages/insforge_auth/lib/src/auth_client.dart`
- Test: `packages/insforge_auth/test/auth_client_refresh_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_refresh_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('refreshAccessToken sends the stored refresh token and updates state',
      () async {
    await storage.write('insforge_refresh_token', 'stored-refresh');

    adapter.onPost(
      '/api/auth/refresh',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-1', 'email': 'a@b.com'},
        'accessToken': 'new-access',
        'refreshToken': 'new-refresh',
      }),
      data: <String, dynamic>{'refreshToken': 'stored-refresh'},
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final states = <AuthState>[];
    final sub = auth.onAuthStateChange.listen(states.add);

    final response = await auth.refreshAccessToken();

    expect(response.accessToken, 'new-access');
    expect(http.accessToken, 'new-access');
    expect(await storage.read('insforge_access_token'), 'new-access');
    expect(await storage.read('insforge_refresh_token'), 'new-refresh');

    await Future<void>.delayed(Duration.zero);
    expect(states.single.event, AuthChangeEvent.tokenRefreshed);
    await sub.cancel();
  });

  test('refreshAccessToken throws when no refresh token is stored', () async {
    expect(
      () => auth.refreshAccessToken(),
      throwsA(isA<InsforgeAuthException>()),
    );
  });

  test('getCurrentUser fetches the current session user', () async {
    adapter.onGet(
      '/api/auth/sessions/current',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{
          'id': 'u-99',
          'email': 'me@here.com',
          'emailVerified': true,
        },
      }),
    );

    final user = await auth.getCurrentUser();
    expect(user.id, 'u-99');
    expect(user.email, 'me@here.com');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_client_refresh_test.dart`
Expected: FAIL — `refreshAccessToken` throws `UnimplementedError`; `getCurrentUser` not defined.

- [ ] **Step 3: Replace the placeholder `refreshAccessToken` and add `getCurrentUser`**

In `auth_client.dart`, replace the placeholder method:

```dart
  /// Refreshes the access token using the persisted refresh token.
  /// Implemented in Task 14.
  Future<AuthResponse> refreshAccessToken() {
    throw UnimplementedError('refreshAccessToken is implemented in Task 14');
  }
```

with:

```dart
  /// Refreshes the access token using the persisted refresh token. Persists the
  /// new tokens and emits [AuthChangeEvent.tokenRefreshed].
  Future<AuthResponse> refreshAccessToken() async {
    final refreshToken = await _storage.read(kRefreshTokenKey);
    if (refreshToken == null) {
      throw InsforgeAuthException('No refresh token available');
    }
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/refresh',
      data: <String, dynamic>{'refreshToken': refreshToken},
      queryParameters: _clientTypeQuery,
    );
    final response = AuthResponse.fromJson(res.data!);
    await _applySession(response.toSession(), AuthChangeEvent.tokenRefreshed);
    return response;
  }

  /// Fetches the currently authenticated user from the access token.
  Future<User> getCurrentUser() async {
    final res = await _http.request<Map<String, dynamic>>(
      'GET',
      '/api/auth/sessions/current',
    );
    return User.fromJson(Map<String, dynamic>.from(res.data!['user'] as Map));
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_refresh_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_client.dart packages/insforge_auth/test/auth_client_refresh_test.dart
git commit -m "feat(auth): add refreshAccessToken and getCurrentUser"
```

---

## Task 15: Email verification + password reset flows

**Files:**
- Modify: `packages/insforge_auth/lib/src/auth_client.dart`
- Test: `packages/insforge_auth/test/auth_client_email_test.dart`

Endpoints (from auth.yaml):
`POST /api/auth/email/send-verification` `{email}`;
`POST /api/auth/email/verify` `{email, otp}` (token-issuing → `client_type=mobile`);
`POST /api/auth/email/send-reset-password` `{email}`;
`POST /api/auth/email/exchange-reset-password-token` `{email, code}` → `{token, expiresAt}`;
`POST /api/auth/email/reset-password` `{newPassword, otp}`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_email_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('sendVerificationEmail posts the email', () async {
    adapter.onPost(
      '/api/auth/email/send-verification',
      (server) => server.reply(202, <String, dynamic>{
        'success': true,
        'message': 'sent',
      }),
      data: <String, dynamic>{'email': 'a@b.com'},
    );

    await auth.sendVerificationEmail('a@b.com');
  });

  test('verifyEmail establishes and persists a session', () async {
    adapter.onPost(
      '/api/auth/email/verify',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-1', 'email': 'a@b.com'},
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      }),
      data: <String, dynamic>{'email': 'a@b.com', 'otp': '123456'},
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final response = await auth.verifyEmail(email: 'a@b.com', otp: '123456');
    expect(response.accessToken, 'access-1');
    expect(http.accessToken, 'access-1');
    expect(await storage.read('insforge_access_token'), 'access-1');
  });

  test('sendPasswordReset posts the email', () async {
    adapter.onPost(
      '/api/auth/email/send-reset-password',
      (server) => server.reply(202, <String, dynamic>{
        'success': true,
        'message': 'sent',
      }),
      data: <String, dynamic>{'email': 'a@b.com'},
    );

    await auth.sendPasswordReset('a@b.com');
  });

  test('exchangeResetPasswordToken returns a reset token', () async {
    adapter.onPost(
      '/api/auth/email/exchange-reset-password-token',
      (server) => server.reply(200, <String, dynamic>{
        'token': 'reset-token-1',
        'expiresAt': '2026-06-08T12:00:00.000Z',
      }),
      data: <String, dynamic>{'email': 'a@b.com', 'code': '123456'},
    );

    final result =
        await auth.exchangeResetPasswordToken(email: 'a@b.com', code: '123456');
    expect(result.token, 'reset-token-1');
    expect(result.expiresAt?.hour, 12);
  });

  test('resetPassword posts the new password and otp', () async {
    adapter.onPost(
      '/api/auth/email/reset-password',
      (server) => server.reply(200, <String, dynamic>{
        'message': 'Password reset successfully',
      }),
      data: <String, dynamic>{'newPassword': 'newpw123', 'otp': 'reset-token-1'},
    );

    await auth.resetPassword(otp: 'reset-token-1', newPassword: 'newpw123');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_client_email_test.dart`
Expected: FAIL — the email/reset methods are not defined.

- [ ] **Step 3: Add the email/reset methods to `auth_client.dart`**

Insert after `getCurrentUser`:

```dart
  // ---------------------------------------------------------------------------
  // Email verification
  // ---------------------------------------------------------------------------

  /// Sends (or resends) a verification email/code to [email].
  Future<void> sendVerificationEmail(String email) async {
    await _http.request<dynamic>(
      'POST',
      '/api/auth/email/send-verification',
      data: <String, dynamic>{'email': email},
    );
  }

  /// Verifies an email with a 6-digit [otp], establishing a session.
  Future<AuthResponse> verifyEmail({
    String? email,
    required String otp,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/email/verify',
      data: <String, dynamic>{
        if (email != null) 'email': email,
        'otp': otp,
      },
      queryParameters: _clientTypeQuery,
    );
    final response = AuthResponse.fromJson(res.data!);
    await _applySession(response.toSession(), AuthChangeEvent.signedIn);
    return response;
  }

  // ---------------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------------

  /// Sends a password-reset email/code to [email].
  Future<void> sendPasswordReset(String email) async {
    await _http.request<dynamic>(
      'POST',
      '/api/auth/email/send-reset-password',
      data: <String, dynamic>{'email': email},
    );
  }

  /// Exchanges a 6-digit reset [code] for a single-use reset token.
  Future<ResetTokenResponse> exchangeResetPasswordToken({
    required String email,
    required String code,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/email/exchange-reset-password-token',
      data: <String, dynamic>{'email': email, 'code': code},
    );
    return ResetTokenResponse.fromJson(res.data!);
  }

  /// Resets the password using a reset [otp] (the token from
  /// [exchangeResetPasswordToken] or a magic-link token).
  Future<void> resetPassword({
    required String otp,
    required String newPassword,
  }) async {
    await _http.request<dynamic>(
      'POST',
      '/api/auth/email/reset-password',
      data: <String, dynamic>{'newPassword': newPassword, 'otp': otp},
    );
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_email_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_client.dart packages/insforge_auth/test/auth_client_email_test.dart
git commit -m "feat(auth): add email verification and password reset flows"
```

---

## Task 16: OAuth — `getOAuthUrl` + `handleOAuthCallback`

**Files:**
- Modify: `packages/insforge_auth/lib/src/auth_client.dart`
- Test: `packages/insforge_auth/test/auth_client_oauth_test.dart`

From auth.yaml: `GET /api/auth/oauth/{provider}?redirect_uri=...&code_challenge=...`
returns `{authUrl}`. After the provider callback, the app's `redirect_uri`
receives an `insforge_code` query parameter. `POST /api/auth/oauth/exchange`
(`client_type=mobile`) with `{code, code_verifier}` returns `{user, accessToken,
refreshToken}`.

> **Design note:** the design lists `getOAuthUrl(...) -> String`, but the URL is
> produced by a network call (the backend builds the provider URL). This plan
> therefore makes `getOAuthUrl` return `Future<String>` (the `authUrl` from the
> response body), matching the Kotlin/Swift SDKs.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_oauth_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('getOAuthUrl calls the provider endpoint and returns authUrl', () async {
    adapter.onGet(
      '/api/auth/oauth/google',
      (server) => server.reply(200, <String, dynamic>{
        'authUrl': 'https://accounts.google.com/o/oauth2/auth?x=1',
      }),
      queryParameters: <String, dynamic>{
        'redirect_uri': 'myapp://callback',
        'code_challenge': 'challenge-abc',
      },
    );

    final url = await auth.getOAuthUrl(
      provider: OAuthProvider.google,
      redirectUri: 'myapp://callback',
      codeChallenge: 'challenge-abc',
    );

    expect(url, 'https://accounts.google.com/o/oauth2/auth?x=1');
  });

  test('handleOAuthCallback exchanges insforge_code and establishes a session',
      () async {
    adapter.onPost(
      '/api/auth/oauth/exchange',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-oauth', 'email': 'o@auth.com'},
        'accessToken': 'oauth-access',
        'refreshToken': 'oauth-refresh',
      }),
      data: <String, dynamic>{
        'code': 'insforge-code-1',
        'code_verifier': 'verifier-1',
      },
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final callback = Uri.parse('myapp://callback?insforge_code=insforge-code-1');
    final response = await auth.handleOAuthCallback(callback, 'verifier-1');

    expect(response.accessToken, 'oauth-access');
    expect(http.accessToken, 'oauth-access');
    expect(auth.currentUser?.id, 'u-oauth');
    expect(await storage.read('insforge_refresh_token'), 'oauth-refresh');
  });

  test('handleOAuthCallback throws when insforge_code is missing', () async {
    final callback = Uri.parse('myapp://callback?error=access_denied');
    expect(
      () => auth.handleOAuthCallback(callback, 'verifier-1'),
      throwsA(isA<InsforgeAuthException>()),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_client_oauth_test.dart`
Expected: FAIL — `getOAuthUrl`/`handleOAuthCallback` not defined.

- [ ] **Step 3: Add the OAuth methods to `auth_client.dart`**

Insert after `resetPassword`:

```dart
  // ---------------------------------------------------------------------------
  // OAuth (PKCE)
  // ---------------------------------------------------------------------------

  /// Requests the provider authorization URL for a PKCE flow. The app should
  /// open the returned URL in a browser, then pass the callback URI to
  /// [handleOAuthCallback] along with the original [PkceHelper] verifier.
  Future<String> getOAuthUrl({
    required OAuthProvider provider,
    required String redirectUri,
    required String codeChallenge,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'GET',
      '/api/auth/oauth/${provider.wireName}',
      queryParameters: <String, dynamic>{
        'redirect_uri': redirectUri,
        'code_challenge': codeChallenge,
      },
    );
    return res.data!['authUrl'] as String;
  }

  /// Completes a PKCE OAuth flow: extracts `insforge_code` from [callbackUri],
  /// exchanges it (with [codeVerifier]) for a session, and persists/emits.
  Future<AuthResponse> handleOAuthCallback(
    Uri callbackUri,
    String codeVerifier,
  ) async {
    final code = callbackUri.queryParameters['insforge_code'];
    if (code == null || code.isEmpty) {
      throw InsforgeAuthException(
        'OAuth callback is missing the insforge_code parameter',
      );
    }
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/oauth/exchange',
      data: <String, dynamic>{'code': code, 'code_verifier': codeVerifier},
      queryParameters: _clientTypeQuery,
    );
    final response = AuthResponse.fromJson(res.data!);
    await _applySession(response.toSession(), AuthChangeEvent.signedIn);
    return response;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_oauth_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_client.dart packages/insforge_auth/test/auth_client_oauth_test.dart
git commit -m "feat(auth): add PKCE OAuth getOAuthUrl + handleOAuthCallback"
```

---

## Task 17: Profile — `getProfile` + `updateProfile`

**Files:**
- Modify: `packages/insforge_auth/lib/src/auth_client.dart`
- Test: `packages/insforge_auth/test/auth_client_profile_test.dart`

From auth.yaml: `GET /api/auth/profiles/{userId}` → `ProfileResponse`;
`PATCH /api/auth/profiles/current` `{profile}` → `ProfileResponse`. After a
successful update, the in-memory user's `profile` is refreshed and a
`userUpdated` event is emitted.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_profile_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('getProfile fetches a user profile by id', () async {
    adapter.onGet(
      '/api/auth/profiles/u-42',
      (server) => server.reply(200, <String, dynamic>{
        'id': 'u-42',
        'profile': <String, dynamic>{'name': 'Grace', 'avatar_url': 'g.png'},
      }),
    );

    final profile = await auth.getProfile('u-42');
    expect(profile.id, 'u-42');
    expect(profile.profile['name'], 'Grace');
  });

  test('updateProfile patches the current profile and emits userUpdated',
      () async {
    // Sign in first so there is a current session to update.
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{
          'id': 'u-1',
          'email': 'a@b.com',
          'profile': <String, dynamic>{'name': 'Old'},
        },
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );
    adapter.onPatch(
      '/api/auth/profiles/current',
      (server) => server.reply(200, <String, dynamic>{
        'id': 'u-1',
        'profile': <String, dynamic>{'name': 'New', 'avatar_url': 'n.png'},
      }),
      data: <String, dynamic>{
        'profile': <String, dynamic>{'name': 'New', 'avatar_url': 'n.png'},
      },
    );

    await auth.signIn(email: 'a@b.com', password: 'pw');

    final states = <AuthState>[];
    final sub = auth.onAuthStateChange.listen(states.add);

    final updated = await auth.updateProfile(<String, dynamic>{
      'name': 'New',
      'avatar_url': 'n.png',
    });

    expect(updated.profile['name'], 'New');
    // In-memory user reflects the new profile.
    expect(auth.currentUser?.name, 'New');
    expect(auth.currentUser?.avatarUrl, 'n.png');

    await Future<void>.delayed(Duration.zero);
    expect(states.single.event, AuthChangeEvent.userUpdated);
    await sub.cancel();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_client_profile_test.dart`
Expected: FAIL — `getProfile`/`updateProfile` not defined.

- [ ] **Step 3: Add the profile methods to `auth_client.dart`**

Insert after `handleOAuthCallback`:

```dart
  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  /// Fetches the public profile for [userId].
  Future<Profile> getProfile(String userId) async {
    final res = await _http.request<Map<String, dynamic>>(
      'GET',
      '/api/auth/profiles/$userId',
    );
    return Profile.fromJson(res.data!);
  }

  /// Updates the current user's profile. Refreshes the in-memory user and
  /// emits [AuthChangeEvent.userUpdated] when a session is active.
  Future<Profile> updateProfile(Map<String, dynamic> profile) async {
    final res = await _http.request<Map<String, dynamic>>(
      'PATCH',
      '/api/auth/profiles/current',
      data: <String, dynamic>{'profile': profile},
    );
    final updated = Profile.fromJson(res.data!);

    final session = _currentSession;
    if (session != null) {
      final current = session.user;
      final mergedUser = User(
        id: current.id,
        email: current.email,
        emailVerified: current.emailVerified,
        providers: current.providers,
        profile: updated.profile,
        metadata: current.metadata,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
      );
      final newSession = session.copyWith(user: mergedUser);
      _currentSession = newSession;
      await _storage.write(kUserKey, jsonEncode(mergedUser.toJson()));
      _stateController.add(
        AuthState(AuthChangeEvent.userUpdated, newSession),
      );
    }
    return updated;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_profile_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_client.dart packages/insforge_auth/test/auth_client_profile_test.dart
git commit -m "feat(auth): add getProfile and updateProfile"
```

---

## Task 18: `restoreSession` — rehydrate + proactive refresh

**Files:**
- Modify: `packages/insforge_auth/lib/src/auth_client.dart`
- Test: `packages/insforge_auth/test/auth_client_restore_test.dart`

`restoreSession()` reads the persisted refresh token, access token, and user.
When the access token's `exp` (via `decodeJwtExpiry`) is within
`kProactiveRefreshLeeway` (or absent), it refreshes; otherwise it restores the
stored session in memory and sets `http.accessToken`. Returns the restored (or
refreshed) [Session], or null when nothing is stored.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_restore_test.dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

/// Builds an unsigned JWT whose `exp` is [secondsFromNow] in the future.
String _jwtExpiringIn(Duration delta) {
  final exp =
      (DateTime.now().toUtc().add(delta).millisecondsSinceEpoch / 1000).floor();
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'});
  final body = seg(<String, dynamic>{'sub': 'u-1', 'exp': exp});
  return '$header.$body.sig';
}

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('returns null when nothing is stored', () async {
    final restored = await auth.restoreSession();
    expect(restored, isNull);
    expect(auth.currentSession, isNull);
  });

  test('restores a stored session with a fresh (far-future) token', () async {
    final token = _jwtExpiringIn(const Duration(hours: 1));
    await storage.write('insforge_access_token', token);
    await storage.write('insforge_refresh_token', 'stored-refresh');
    await storage.write(
      'insforge_user',
      jsonEncode(<String, dynamic>{'id': 'u-1', 'email': 'a@b.com'}),
    );

    final restored = await auth.restoreSession();

    expect(restored, isNotNull);
    expect(restored!.accessToken, token);
    expect(auth.currentUser?.id, 'u-1');
    expect(http.accessToken, token);
  });

  test('proactively refreshes when the stored token expires within leeway',
      () async {
    final nearlyExpired = _jwtExpiringIn(const Duration(seconds: 5));
    await storage.write('insforge_access_token', nearlyExpired);
    await storage.write('insforge_refresh_token', 'stored-refresh');
    await storage.write(
      'insforge_user',
      jsonEncode(<String, dynamic>{'id': 'u-1', 'email': 'a@b.com'}),
    );

    adapter.onPost(
      '/api/auth/refresh',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-1', 'email': 'a@b.com'},
        'accessToken': 'refreshed-access',
        'refreshToken': 'refreshed-refresh',
      }),
      data: <String, dynamic>{'refreshToken': 'stored-refresh'},
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final restored = await auth.restoreSession();

    expect(restored?.accessToken, 'refreshed-access');
    expect(http.accessToken, 'refreshed-access');
    expect(await storage.read('insforge_access_token'), 'refreshed-access');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_auth && dart test test/auth_client_restore_test.dart`
Expected: FAIL — `restoreSession` not defined.

- [ ] **Step 3: Add `restoreSession` to `auth_client.dart`**

Insert after `updateProfile`:

```dart
  // ---------------------------------------------------------------------------
  // Session restoration
  // ---------------------------------------------------------------------------

  /// Rehydrates a persisted session. When the stored access token is missing,
  /// already expired, or expiring within [kProactiveRefreshLeeway], refreshes
  /// using the stored refresh token; otherwise restores the stored session.
  /// Returns the restored/refreshed [Session], or null when nothing is stored.
  Future<Session?> restoreSession() async {
    final refreshToken = await _storage.read(kRefreshTokenKey);
    final accessToken = await _storage.read(kAccessTokenKey);
    final userJson = await _storage.read(kUserKey);

    if (refreshToken == null && accessToken == null) {
      return null;
    }

    final needsRefresh = _accessTokenNeedsRefresh(accessToken);

    if (needsRefresh && refreshToken != null && _options.autoRefreshToken) {
      try {
        final response = await refreshAccessToken();
        return response.toSession();
      } catch (_) {
        // Fall through to restoring the stored (possibly stale) session.
      }
    }

    if (accessToken != null && userJson != null) {
      final user = User.fromJson(
        Map<String, dynamic>.from(jsonDecode(userJson) as Map),
      );
      final session = Session(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      );
      _currentSession = session;
      _http.accessToken = accessToken;
      _stateController.add(AuthState(AuthChangeEvent.signedIn, session));
      return session;
    }

    return null;
  }

  bool _accessTokenNeedsRefresh(String? accessToken) {
    if (accessToken == null) return true;
    final expiry = decodeJwtExpiry(accessToken);
    if (expiry == null) return true;
    final threshold = DateTime.now().toUtc().add(kProactiveRefreshLeeway);
    return expiry.isBefore(threshold);
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_restore_test.dart`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_auth/lib/src/auth_client.dart packages/insforge_auth/test/auth_client_restore_test.dart
git commit -m "feat(auth): add restoreSession with proactive refresh"
```

---

## Task 19: Refresh callback registration — 401 on a protected GET triggers refresh

**Files:**
- Test: `packages/insforge_auth/test/auth_client_refresh_callback_test.dart`

The implementation already registers the callback in the `AuthClient`
constructor (Task 11). This task locks in the end-to-end behavior using the
sequence-adapter pattern from Plan 1 Task 12: a custom `HttpClientAdapter`
returns 401 on the first protected call, then 200 once the refreshed token is
present. The refresh endpoint itself returns new tokens.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_auth/test/auth_client_refresh_callback_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

/// Sequence adapter:
/// - The first GET to the protected path returns 401.
/// - A POST to /api/auth/refresh returns new tokens.
/// - The retried GET (now carrying the fresh token) returns 200.
class SequenceAdapter implements HttpClientAdapter {
  final List<String?> protectedAuthHeaders = <String?>[];
  int protectedCalls = 0;
  int refreshCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;

    if (path.contains('/api/auth/refresh')) {
      refreshCalls++;
      return ResponseBody.fromString(
        '{"user":{"id":"u-1","email":"a@b.com"},'
        '"accessToken":"fresh-access","refreshToken":"fresh-refresh"}',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }

    // Protected resource.
    protectedCalls++;
    protectedAuthHeaders.add(options.headers['Authorization'] as String?);
    if (protectedCalls == 1) {
      return ResponseBody.fromString(
        '{"error":"UNAUTHORIZED","message":"expired","statusCode":401}',
        401,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a 401 on a protected GET triggers the registered refresh callback',
      () async {
    final http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    final adapter = SequenceAdapter();
    http.dio.httpClientAdapter = adapter;

    final storage = InMemorySessionStorage();
    await storage.write('insforge_refresh_token', 'stored-refresh');

    // Constructing AuthClient registers the refresh callback with http.
    final auth = AuthClient(http, storage);
    http.accessToken = 'stale-access';
    // Reference auth so the analyzer does not flag it as unused.
    expect(auth.currentSession, isNull);

    final response =
        await http.request<dynamic>('GET', '/api/database/records/posts');

    expect(response.statusCode, 200);
    expect(adapter.refreshCalls, 1);
    expect(adapter.protectedCalls, 2);
    expect(adapter.protectedAuthHeaders[0], 'Bearer stale-access');
    expect(adapter.protectedAuthHeaders[1], 'Bearer fresh-access');

    // Refresh persisted the new tokens.
    expect(await storage.read('insforge_access_token'), 'fresh-access');
    expect(await storage.read('insforge_refresh_token'), 'fresh-refresh');
  });
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `cd packages/insforge_auth && dart test test/auth_client_refresh_callback_test.dart`
Expected: PASS — the constructor-registered callback (Task 11) drives the
core's single-flight 401 retry (Plan 1 Task 12).

- [ ] **Step 3: Commit**

```bash
git add packages/insforge_auth/test/auth_client_refresh_callback_test.dart
git commit -m "test(auth): cover 401-triggered refresh via registered callback"
```

---

## Task 20: Full suite + analyze + final export sweep

**Files:**
- Verify: `packages/insforge_auth/lib/insforge_auth.dart` exports every public type.

- [ ] **Step 1: Confirm the export file lists all public types**

`packages/insforge_auth/lib/insforge_auth.dart` should contain exactly these
export lines (in addition to the `library` directive):

```dart
// packages/insforge_auth/lib/insforge_auth.dart
/// Authentication for the InsForge Flutter SDK.
library insforge_auth;

export 'src/auth_client.dart';
export 'src/auth_options.dart';
export 'src/auth_state.dart';
export 'src/enums.dart';
export 'src/jwt.dart';
export 'src/models/auth_response.dart';
export 'src/models/profile.dart';
export 'src/models/reset_token_response.dart';
export 'src/models/session.dart';
export 'src/models/sign_up_response.dart';
export 'src/models/user.dart';
export 'src/pkce.dart';
```

If any line is missing, add it.

- [ ] **Step 2: Run the full package test suite**

Run: `cd packages/insforge_auth && dart test`
Expected: every test file PASSES.

- [ ] **Step 3: Analyze the package**

Run: `cd packages/insforge_auth && dart analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit any export fixes**

```bash
git add packages/insforge_auth/lib/insforge_auth.dart
git commit -m "chore(auth): finalize public exports"
```

(If Step 1 required no changes, skip this commit.)

---

## Self-Review Notes

- **Spec coverage (design §4.2):** `AuthClient(http, storage, {options})`
  with `signUp` (Task 12), `signIn` (Task 11), `signOut` (Task 13),
  `getCurrentUser` + `refreshAccessToken` (Task 14), `sendVerificationEmail` /
  `verifyEmail` / `sendPasswordReset` / `exchangeResetPasswordToken` /
  `resetPassword` (Task 15), `getOAuthUrl` / `handleOAuthCallback` (Task 16),
  `getProfile` / `updateProfile` (Task 17), and `restoreSession` (Task 18).
  Reactive state (`onAuthStateChange` broadcast stream, `currentUser`,
  `currentSession`) is in Task 11; `AuthState`/`AuthChangeEvent` in Tasks 2/10.
  Behavior: `client_type=mobile` on token-issuing calls (signIn/signUp/refresh/
  verify/oauth-exchange — Tasks 11, 12, 14, 15, 16); persistence under
  `insforge_refresh_token` / `insforge_access_token` / `insforge_user` (Task 11
  `_persist`); `http.accessToken` set + auth state emitted on success;
  `signOut` clears store + token + emits `signedOut` (Task 13); proactive
  refresh within ~30s of `exp` (Task 18 `kProactiveRefreshLeeway`); refresh
  callback registered with the core client (Task 11 constructor, end-to-end in
  Task 19). Models: `User` (+ `name`/`avatarUrl`), `Session`, `AuthResponse`,
  `SignUpResponse` (+ `hasSession`), `Profile`, `ResetTokenResponse`,
  `OAuthProvider` (11 providers with `wireName`), `ClientType` (default mobile),
  `AuthOptions`, `PkceHelper`, `decodeJwtExpiry`. Covered.

- **Type consistency with Plan 1 (core):** imports only the public names Plan 1
  guarantees — `InsforgeHttpClient` (`.request`, `.accessToken` get/set,
  `.dio`, `.registerRefreshCallback`), `RefreshCallback`, `SessionStorage` /
  `InMemorySessionStorage`, `InsforgeAuthException`, `InsforgeHttpException`,
  `parseInsforgeDate`. `AuthClient` is the writer of `http.accessToken` and the
  registrar of `RefreshCallback` (matching Plan 1's Self-Review note that auth
  fills the `AuthTokenStore` role). The refresh callback returns the new access
  token `String`, as required by `RefreshCallback = Future<String> Function()`.

- **Field-name verification against `openapi/auth.yaml` (deviations from the
  design prose, all matched to the authoritative contract):**
  - OAuth init `GET /api/auth/oauth/{provider}` returns `{authUrl}` (a JSON
    body), not a directly-constructed URL — so `getOAuthUrl` returns
    `Future<String>` (the `authUrl`), not a synchronous `String` as the design
    prose implied. Documented inline in Task 16.
  - The OAuth callback delivers the code in the `insforge_code` query
    parameter (not `code`); `handleOAuthCallback` extracts `insforge_code` and
    POSTs `{code, code_verifier}` to `/api/auth/oauth/exchange`.
  - `verifyEmail` body uses `otp` (6-digit) + `email`; auth.yaml marks both
    required, so `email` is accepted as optional in the signature but sent when
    provided.
  - `exchange-reset-password-token` request is `{email, code}` and the response
    is `{token, expiresAt}` → `ResetTokenResponse(token, expiresAt)`.
  - `reset-password` body is `{newPassword, otp}` (the `otp` here is the reset
    token from the exchange step or a magic link).
  - Refresh body for mobile clients is `{refreshToken}` (camelCase, per the
    auth.yaml `client_type=mobile` description), with `client_type=mobile`.
  - `User` `profile`/`metadata` are typed `Map<String, dynamic>?` (auth.yaml
    `additionalProperties: true`), so `name`/`avatarUrl` getters cast
    `profile['name']` / `profile['avatar_url']` to `String?`.

- **Deferred / out of scope:** `signInWithOAuth` browser-launch convenience and
  deep-link capture (design §4.7) live in the umbrella/sample (Plan 7); this
  package provides the network primitives (`getOAuthUrl`, `handleOAuthCallback`).
  Admin endpoints, `public-config`, custom OAuth providers, and the link-based
  (cookie) email flows are intentionally omitted from v1's mobile client.
