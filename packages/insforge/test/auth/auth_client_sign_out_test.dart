// packages/insforge_auth/test/auth_client_sign_out_test.dart
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
