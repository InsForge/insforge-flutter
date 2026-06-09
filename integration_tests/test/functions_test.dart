// integration_tests/test/functions_test.dart
//
// Edge Functions module integration tests. Needs only core config.
//
// Prerequisite (optional): a `hello-world` function deployed on the project.
// Both a 2xx response and a structured InsforgeHttpException are acceptable
// outcomes for an existing slug; a clearly non-existent slug must throw.
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

const String _slug = 'hello-world';

void main() {
  group(
    'Functions Module',
    () {
      late FunctionsClient functions;

      setUpAll(() {
        functions = FunctionsClient(env.newHttpClient());
      });

      test('invoke hello-world (POST, default) – 2xx or structured error',
          () async {
        try {
          final data = await functions.invoke(
            _slug,
            body: <String, dynamic>{'name': 'SDK Integration Test'},
          );
          expect(data, anything);
        } on InsforgeHttpException catch (e) {
          expect(e.statusCode, greaterThanOrEqualTo(400));
          expect(e.message, isA<String>());
        }
      });

      test('invoke hello-world with GET', () async {
        try {
          final data = await functions.invoke(_slug, method: 'GET');
          expect(data, anything);
        } on InsforgeHttpException catch (e) {
          expect(e.statusCode, greaterThanOrEqualTo(400));
        }
      });

      test('invoke hello-world with custom headers', () async {
        try {
          final data = await functions.invoke(
            _slug,
            body: <String, dynamic>{'echo': true},
            headers: <String, String>{
              'X-Custom-Test': 'integration',
              'X-Request-Id': 'test-${DateTime.now().microsecondsSinceEpoch}',
            },
          );
          expect(data, anything);
        } on InsforgeHttpException catch (e) {
          expect(e.statusCode, greaterThanOrEqualTo(400));
        }
      });

      test('invoke a non-existent slug throws (404-ish)', () async {
        final slug = 'nonexistent-fn-${DateTime.now().microsecondsSinceEpoch}';
        await expectLater(
          functions.invoke(slug),
          throwsA(
            isA<InsforgeHttpException>().having(
              (InsforgeHttpException e) => e.statusCode,
              'statusCode',
              greaterThanOrEqualTo(400),
            ),
          ),
        );
      });
    },
    skip: env.coreSkipReason,
  );
}
