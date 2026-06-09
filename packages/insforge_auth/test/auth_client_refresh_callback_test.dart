// packages/insforge_auth/test/auth_client_refresh_callback_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

/// Sequence adapter:
/// - The first GET to the protected path returns 401.
/// - A POST to /api/auth/refresh returns new tokens.
/// - The retried GET (now carrying the fresh token) returns 200.
class SequenceAdapter implements HttpClientAdapter {
  final List<String?> protectedAuthHeaders = <String?>[];
  int protectedCalls = 0;
  int refreshCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;

    if (path.contains('/api/auth/refresh')) {
      refreshCalls++;
      return ResponseBody.fromString(
        '{"user":{"id":"u-1","email":"a@b.com"},'
        '"accessToken":"fresh-access","refreshToken":"fresh-refresh"}',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }

    // Protected resource.
    protectedCalls++;
    protectedAuthHeaders.add(options.headers['Authorization'] as String?);
    if (protectedCalls == 1) {
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
  test('a 401 on a protected GET triggers the registered refresh callback',
      () async {
    final http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    final adapter = SequenceAdapter();
    http.dio.httpClientAdapter = adapter;

    final storage = InMemorySessionStorage();
    await storage.write('insforge_refresh_token', 'stored-refresh');

    // Constructing AuthClient registers the refresh callback with http.
    final auth = AuthClient(http, storage);
    http.accessToken = 'stale-access';
    // Reference auth so the analyzer does not flag it as unused.
    expect(auth.currentSession, isNull);

    final response =
        await http.request<dynamic>('GET', '/api/database/records/posts');

    expect(response.statusCode, 200);
    expect(adapter.refreshCalls, 1);
    expect(adapter.protectedCalls, 2);
    expect(adapter.protectedAuthHeaders[0], 'Bearer stale-access');
    expect(adapter.protectedAuthHeaders[1], 'Bearer fresh-access');

    // Refresh persisted the new tokens.
    expect(await storage.read('insforge_access_token'), 'fresh-access');
    expect(await storage.read('insforge_refresh_token'), 'fresh-refresh');
  });
}
