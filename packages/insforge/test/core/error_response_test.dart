// packages/insforge_core/test/error_response_test.dart
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

void main() {
  group('ErrorResponse.fromJson', () {
    test('parses the auth/records envelope', () {
      final r = ErrorResponse.fromJson(<String, dynamic>{
        'error': 'AUTH_INVALID_CREDENTIALS',
        'message': 'Invalid email or password',
        'statusCode': 401,
        'nextActions': 'Check the credentials and retry.',
      });
      expect(r.error, 'AUTH_INVALID_CREDENTIALS');
      expect(r.message, 'Invalid email or password');
      expect(r.statusCode, 401);
      expect(r.nextActions, 'Check the credentials and retry.');
    });

    test('parses the functions/ai envelope (details + code, no message)', () {
      final r = ErrorResponse.fromJson(<String, dynamic>{
        'error': 'BadRequest',
        'details': 'model is required',
        'code': 'invalid_request',
      });
      // error code prefers `error`, falling back to `code`.
      expect(r.error, 'BadRequest');
      // message falls back to details when message is absent.
      expect(r.message, 'model is required');
      expect(r.statusCode, isNull);
      expect(r.nextActions, isNull);
    });

    test('falls back to a generic message when nothing usable is present', () {
      final r = ErrorResponse.fromJson(<String, dynamic>{});
      expect(r.message, 'Unknown error');
    });
  });
}
