// packages/insforge_core/test/http_client_auth_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

/// Records the headers of each request and returns a fixed JSON 200.
class RecordingAdapter implements HttpClientAdapter {
  final List<Map<String, List<String>>> requests = <Map<String, List<String>>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(Map<String, List<String>>.from(options.headers.map(
      (k, v) => MapEntry(k, <String>[v.toString()]),
    ),),);
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
  test('injects anon key as Bearer when no session token is set', () async {
    final adapter = RecordingAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon-123',
    );
    client.dio.httpClientAdapter = adapter;

    await client.request<dynamic>('GET', '/api/database/records/posts');

    expect(adapter.requests.single['Authorization'], <String>['Bearer anon-123']);
  });

  test('prefers the session access token over the anon key', () async {
    final adapter = RecordingAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon-123',
    );
    client.dio.httpClientAdapter = adapter;
    client.accessToken = 'user-jwt';

    await client.request<dynamic>('GET', '/api/database/records/posts');

    expect(adapter.requests.single['Authorization'], <String>['Bearer user-jwt']);
  });

  test('adds x-api-key when configured', () async {
    final adapter = RecordingAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon-123',
      apiKey: 'apikey-xyz',
    );
    client.dio.httpClientAdapter = adapter;

    await client.request<dynamic>('GET', '/api/storage/buckets');

    expect(adapter.requests.single['x-api-key'], <String>['apikey-xyz']);
  });
}
