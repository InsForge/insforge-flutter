// packages/insforge_auth/test/auth_client_sign_in_test.dart
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
      throwsA(
        isA<InsforgeHttpException>()
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
  });
}
