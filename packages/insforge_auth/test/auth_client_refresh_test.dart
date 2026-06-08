// packages/insforge_auth/test/auth_client_refresh_test.dart
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
