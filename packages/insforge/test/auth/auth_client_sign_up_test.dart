// packages/insforge_auth/test/auth_client_sign_up_test.dart
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge/insforge.dart';
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
