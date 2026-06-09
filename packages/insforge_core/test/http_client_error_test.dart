// packages/insforge_core/test/http_client_error_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

/// Returns a fixed status + JSON body for every request.
class FixedResponseAdapter implements HttpClientAdapter {
  FixedResponseAdapter(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('maps a non-2xx response to InsforgeHttpException with nextActions',
      () async {
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    client.dio.httpClientAdapter = FixedResponseAdapter(
      404,
      '{"error":"TABLE_NOT_FOUND","message":"No such table","statusCode":404,'
      '"nextActions":"Create the table first."}',
    );

    expect(
      () => client.request<dynamic>('GET', '/api/database/records/nope'),
      throwsA(
        isA<InsforgeHttpException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.error, 'error', 'TABLE_NOT_FOUND')
            .having((e) => e.nextActions, 'nextActions', 'Create the table first.'),
      ),
    );
  });
}
