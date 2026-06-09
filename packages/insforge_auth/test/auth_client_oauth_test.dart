// packages/insforge_auth/test/auth_client_oauth_test.dart
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
