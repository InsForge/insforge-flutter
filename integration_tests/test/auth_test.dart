// integration_tests/test/auth_test.dart
//
// Auth module integration tests. The Dart SDK THROWS on error, so failure
// cases are asserted with `throwsA(isA<InsforgeHttpException>())`.
//
// Signup-flow tests only need core config (base URL + anon key). The
// authenticated tests (sign in with the fixed account, profile, signOut) need
// a pre-verified account (authConfigured).
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

AuthClient _newAuth({InsforgeHttpClient? http}) {
  return AuthClient(http ?? env.newHttpClient(), InMemorySessionStorage());
}

void main() {
  // ==========================================================================
  // Sign-up flow — only needs core config.
  // ==========================================================================
  group(
    'Auth – sign-up flow',
    () {
      test('signUp creates a user (tolerating verification-required)',
          () async {
        final auth = _newAuth();
        final email = env.uniqueEmail('signup');

        final res = await auth.signUp(
          email: email,
          password: testPassword,
          name: 'SDK Integration Test',
        );

        // Two valid shapes: (a) verification disabled → an immediate session
        // with a user; (b) verification required → no session and no user
        // object (only a status flag), per the real backend contract.
        if (res.hasSession) {
          expect(res.accessToken, isNotNull);
          expect(res.user, isNotNull);
          expect(res.user!.email, email);
          expect(res.user!.id, isNotEmpty);
        } else {
          expect(res.requireEmailVerification, isTrue);
        }
      });

      test('signUp rejects a duplicate email', () async {
        final auth = _newAuth();
        final email = env.uniqueEmail('dup');

        await auth.signUp(
          email: email,
          password: testPassword,
          name: 'First',
        );

        await expectLater(
          auth.signUp(email: email, password: testPassword, name: 'Second'),
          throwsA(
            isA<InsforgeHttpException>().having(
              (InsforgeHttpException e) => e.statusCode,
              'statusCode',
              greaterThanOrEqualTo(400),
            ),
          ),
        );
      });

      test('signIn rejects a wrong password', () async {
        final auth = _newAuth();
        final email = env.uniqueEmail('wrongpw');

        await auth.signUp(
          email: email,
          password: testPassword,
          name: 'Wrong Password',
        );

        await expectLater(
          auth.signIn(email: email, password: 'Definitely_Wrong_999!'),
          throwsA(isA<InsforgeException>()),
        );
      });

      test('signIn rejects a non-existent account', () async {
        final auth = _newAuth();
        await expectLater(
          auth.signIn(
            email: env.uniqueEmail('ghost'),
            password: testPassword,
          ),
          throwsA(isA<InsforgeException>()),
        );
      });
    },
    skip: env.coreSkipReason,
  );

  // ==========================================================================
  // Authenticated flow — needs the fixed pre-verified account.
  // ==========================================================================
  group(
    'Auth – authenticated flow',
    () {
      test('signIn with the fixed account then getCurrentUser', () async {
        final http = env.newHttpClient();
        final auth = _newAuth(http: http);

        final res = await auth.signIn(
          email: env.testEmail!,
          password: env.testPassword!,
        );
        expect(res.accessToken, isNotEmpty);
        expect(res.user.email, env.testEmail);

        final user = await auth.getCurrentUser();
        expect(user.id, res.user.id);
        expect(user.email, env.testEmail);
      });

      test('updateProfile then getProfile reflects the change', () async {
        final http = env.newHttpClient();
        final auth = _newAuth(http: http);

        final signIn = await auth.signIn(
          email: env.testEmail!,
          password: env.testPassword!,
        );
        final userId = signIn.user.id;

        final newName = 'Integration ${DateTime.now().millisecondsSinceEpoch}';
        final updated = await auth.updateProfile(<String, dynamic>{
          'name': newName,
        });
        expect(updated.profile['name'], newName);

        final fetched = await auth.getProfile(userId);
        expect(fetched.id, userId);
        expect(fetched.profile['name'], newName);
      });

      test('signOut clears the session', () async {
        final http = env.newHttpClient();
        final auth = _newAuth(http: http);

        await auth.signIn(
          email: env.testEmail!,
          password: env.testPassword!,
        );
        expect(auth.currentUser, isNotNull);

        await auth.signOut();
        expect(auth.currentUser, isNull);
        expect(auth.currentSession, isNull);
      });
    },
    skip: env.authSkipReason,
  );
}
