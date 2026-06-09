// packages/insforge/test/insforge_singleton_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:insforge_flutter/insforge_flutter.dart';

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
