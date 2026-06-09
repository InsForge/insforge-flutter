// packages/insforge_auth/test/auth_client_email_test.dart
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
