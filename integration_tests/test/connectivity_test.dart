// integration_tests/test/connectivity_test.dart
//
// Basic unauthenticated reachability check. Confirms the configured project
// answers HTTP at all — a 2xx or a structured 4xx both prove reachability;
// only a network/transport failure is a hard error.
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

void main() {
  group(
    'Connectivity',
    () {
      test('anon request reaches the backend (2xx or structured HTTP error)',
          () async {
        final http = env.newHttpClient();

        try {
          // Public auth config is an unauthenticated endpoint that should
          // answer on any live project.
          await http.request<dynamic>('GET', '/api/auth/config');
          // A 2xx response proves reachability.
        } on InsforgeHttpException catch (e) {
          // A structured HTTP error (e.g. 401/404) ALSO proves the backend is
          // reachable and speaking the InsForge protocol.
          expect(e.statusCode, greaterThanOrEqualTo(400));
        } on InsforgeNetworkException catch (e) {
          fail('Backend unreachable (network error): ${e.message}');
        }
      });
    },
    skip: env.coreSkipReason,
  );
}
