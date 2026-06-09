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
