// packages/insforge_auth/test/auth_client_otp_test.dart
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

  test('signInWithOtp posts the email to the send-otp endpoint', () async {
    adapter.onPost(
      '/api/auth/email/send-otp',
      (server) => server.reply(202, <String, dynamic>{
        'success': true,
        'message':
            'If sign-in is available for this email, we have sent a '
                'verification code.',
      }),
      data: <String, dynamic>{'email': 'a@b.com'},
    );

    await auth.signInWithOtp(email: 'a@b.com');

    // Requesting a code must not touch the session.
    expect(auth.currentSession, isNull);
    expect(http.accessToken, isNull);
  });

  test('verifyOtp posts method "otp", establishes and persists a session',
      () async {
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{
          'id': 'u-1',
          'email': 'a@b.com',
          'emailVerified': true,
        },
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      }),
      data: <String, dynamic>{
        'method': 'otp',
        'email': 'a@b.com',
        'otp': '123456',
        'name': 'Ada Lovelace',
      },
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final states = <AuthState>[];
    final sub = auth.onAuthStateChange.listen(states.add);

    final response = await auth.verifyOtp(
      email: 'a@b.com',
      otp: '123456',
      name: 'Ada Lovelace',
    );

    expect(response.accessToken, 'access-1');
    expect(response.user.id, 'u-1');

    // Session applied and persisted like every other token-issuing flow.
    expect(http.accessToken, 'access-1');
    expect(await storage.read('insforge_access_token'), 'access-1');
    expect(await storage.read('insforge_refresh_token'), 'refresh-1');

    await Future<void>.delayed(Duration.zero);
    expect(states.single.event, AuthChangeEvent.signedIn);

    await sub.cancel();
  });

  test('verifyOtp omits name when not provided', () async {
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-1', 'email': 'a@b.com'},
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      }),
      data: <String, dynamic>{
        'method': 'otp',
        'email': 'a@b.com',
        'otp': '123456',
      },
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final response = await auth.verifyOtp(email: 'a@b.com', otp: '123456');
    expect(response.accessToken, 'access-1');
  });

  test('verifyOtp throws InsforgeHttpException on an invalid code', () async {
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(401, <String, dynamic>{
        'error': 'AUTH_INVALID_CREDENTIALS',
        'message': 'Invalid or expired verification code',
        'statusCode': 401,
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    expect(
      () => auth.verifyOtp(email: 'a@b.com', otp: '000000'),
      throwsA(
        isA<InsforgeHttpException>()
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );
    expect(auth.currentSession, isNull);
  });
}
