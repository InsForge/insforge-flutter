# InsForge SDK for Dart & Flutter

The official [InsForge](https://insforge.dev) SDK — auth, database, storage,
edge functions, and AI for Dart and Flutter apps.

It ships as two packages:

| Package | Platform | Use it when |
| --- | --- | --- |
| [`insforge`](packages/insforge) | Pure Dart | Server, CLI, Dart-only, or you bring your own session storage |
| [`insforge_flutter`](packages/insforge_flutter) | Flutter | Flutter apps — adds secure session persistence and a one-line initializer |

`insforge_flutter` re-exports everything in `insforge`, so a Flutter app only
depends on `insforge_flutter`.

## Install

**Flutter app:**

```bash
dart pub add insforge_flutter
```

**Pure Dart (server / CLI):**

```bash
dart pub add insforge
```

## Quick start

### Flutter

```dart
import 'package:flutter/material.dart';
import 'package:insforge_flutter/insforge_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Builds a shared client, restores any persisted session, and securely
  // stores tokens via flutter_secure_storage.
  await Insforge.initialize(
    url: 'https://<project>.us-east.insforge.app',
    anonKey: '<your-anon-key>',
    // optional — enables Insforge.instance.ai
    openRouterApiKey: '<your-openrouter-key>',
  );

  runApp(const MyApp());
}

// Anywhere in the app:
final client = Insforge.instance;
await client.auth.signIn(email: 'a@b.com', password: 'secret');
```

### Pure Dart

```dart
import 'package:insforge/insforge.dart';

final client = InsforgeClient(
  'https://<project>.us-east.insforge.app',
  '<your-anon-key>',
  // pure-Dart has no secure storage; supply one or use the in-memory default
  sessionStorage: InMemorySessionStorage(),
);

await client.auth.signIn(email: 'a@b.com', password: 'secret');
```

The shared `InsforgeClient` injects auth headers, performs single-flight 401
token refresh, and maps errors to a typed `InsforgeException` hierarchy for
every module below.

## Modules

### Auth — email/password, OAuth (PKCE), sessions, profiles

```dart
// Email + password
final res = await client.auth.signUp(email: email, password: password);
if (!res.hasSession) {
  // Email-verification (code) flow:
  await client.auth.sendVerificationEmail(email);          // (re)send a code
  await client.auth.verifyEmail(email: email, otp: '123456'); // establishes a session
}
await client.auth.signIn(email: email, password: password);

// React to auth changes
client.auth.onAuthStateChange.listen((AuthState s) => print(s.event));

// PKCE OAuth (the host app opens the URL and captures the redirect)
final verifier = PkceHelper.generateCodeVerifier();
final url = await client.auth.getOAuthUrl(
  provider: OAuthProvider.google,
  redirectUri: 'myapp://auth-callback',
  codeChallenge: PkceHelper.codeChallenge(verifier),
);
final session = await client.auth.handleOAuthCallback(redirectUri, verifier);
```

### Database — PostgREST-style query builder

```dart
final posts = await client.database
    .from('posts')
    .select('id, title, author:profiles!posts_author_id_fkey(name)')
    .eq('status', 'active')
    .gt('score', 10)        // multiple filters on one column are AND-ed
    .lt('score', 100)
    .order('created_at', ascending: false)
    .range(0, 19)
    .execute();

await client.database.from('posts').insert(<String, dynamic>{'title': 'Hi'}).execute();
await client.database.from('posts').eq('id', 1).update(<String, dynamic>{'title': 'Edited'}).execute();
await client.database.from('users').upsert(row, onConflict: 'id').execute();
final total = await client.database.from('posts').count();
```

### Storage — buckets and objects

```dart
final stored = await client.storage
    .from('avatars')
    .upload('users/me.png', bytes); // replaces any existing object at this key
final url = client.storage.from('avatars').getPublicUrl(stored.key);
final files = await client.storage.from('avatars').list(prefix: 'users/');
final data = await client.storage.from('avatars').download('users/me.png');
```

### Functions — edge functions

```dart
final result = await client.functions.invoke(
  'hello-world',
  body: <String, dynamic>{'name': 'Ada'},
);
```

### AI — OpenRouter (OpenAI-compatible)

```dart
// Requires an OpenRouter API key (standalone, not proxied through InsForge).
final stream = client.ai.chat.completions.createStream(
  ChatCompletionRequest(
    model: 'openai/gpt-4o-mini',
    messages: <ChatMessage>[ChatMessage.user('Write a haiku about Dart.')],
  ),
);
await for (final chunk in stream) {
  stdout.write(chunk.choices.first.delta.content ?? '');
}
```

## Session persistence

`insforge` defines the `SessionStorage` interface and an `InMemorySessionStorage`.
`insforge_flutter` adds `SecureSessionStorage` (backed by
`flutter_secure_storage`) and uses it by default, so tokens survive app
restarts on iOS Keychain / Android Keystore.

## Sample app

A full Twitter-style sample (auth + email verification, joined feed,
like/unlike, image upload, streaming AI captions) lives in
[`samples/twitter_app`](samples/twitter_app). See its README for backend setup.

## Testing

```bash
flutter pub get                       # resolve the workspace
dart analyze .                        # static analysis
cd packages/insforge && dart test     # pure-Dart unit tests
cd packages/insforge_flutter && flutter test
```

Live, against-a-real-project integration tests live in
[`integration_tests`](integration_tests) and run only when configured via
environment variables (otherwise they skip):

```bash
cd integration_tests
INSFORGE_INTEGRATION_BASE_URL=... INSFORGE_INTEGRATION_ANON_KEY=... dart test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full developer guide.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
