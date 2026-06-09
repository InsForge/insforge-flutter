// packages/insforge_core/test/logging_interceptor_test.dart
import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  test('redacts Authorization and x-api-key in request logs', () {
    final logs = <String>[];
    final interceptor = LoggingInterceptor(LogLevel.info, sink: logs.add);

    final options = RequestOptions(
      path: '/api/auth/sessions',
      method: 'POST',
      headers: <String, dynamic>{
        'Authorization': 'Bearer super-secret-token',
        'x-api-key': 'secret-key',
      },
    );

    interceptor.onRequest(options, RequestInterceptorHandler());

    final joined = logs.join('\n');
    expect(joined, contains('POST'));
    expect(joined, isNot(contains('super-secret-token')));
    expect(joined, isNot(contains('secret-key')));
    expect(joined, contains('Bearer ***'));
  });

  test('logs nothing at LogLevel.none', () {
    final logs = <String>[];
    final interceptor = LoggingInterceptor(LogLevel.none, sink: logs.add);
    interceptor.onRequest(
      RequestOptions(path: '/x', method: 'GET'),
      RequestInterceptorHandler(),
    );
    expect(logs, isEmpty);
  });
}
