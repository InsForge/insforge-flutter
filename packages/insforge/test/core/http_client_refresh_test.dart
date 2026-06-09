// packages/insforge_core/test/http_client_refresh_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

/// First request to a protected path returns 401; subsequent requests return
/// 200. Records the Authorization header of every call.
class RefreshScenarioAdapter implements HttpClientAdapter {
  int calls = 0;
  final List<String?> authHeaders = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    authHeaders.add(options.headers['Authorization'] as String?);
    if (calls == 1) {
      return ResponseBody.fromString(
        '{"error":"UNAUTHORIZED","message":"expired","statusCode":401}',
        401,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('refreshes once on 401 and retries with the new token', () async {
    final adapter = RefreshScenarioAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    client.dio.httpClientAdapter = adapter;
    client.accessToken = 'stale-token';

    var refreshCalls = 0;
    client.registerRefreshCallback(() async {
      refreshCalls++;
      client.accessToken = 'fresh-token';
      return 'fresh-token';
    });

    final response =
        await client.request<dynamic>('GET', '/api/database/records/posts');

    expect(response.statusCode, 200);
    expect(refreshCalls, 1);
    expect(adapter.calls, 2);
    expect(adapter.authHeaders[0], 'Bearer stale-token');
    expect(adapter.authHeaders[1], 'Bearer fresh-token');
  });

  test('does not attempt refresh for the refresh endpoint itself', () async {
    final adapter = RefreshScenarioAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    client.dio.httpClientAdapter = adapter;
    client.registerRefreshCallback(() async => 'should-not-be-called');

    expect(
      () => client.request<dynamic>('POST', '/api/auth/refresh'),
      throwsA(isA<InsforgeHttpException>()
          .having((e) => e.statusCode, 'statusCode', 401),),
    );
  });
}
