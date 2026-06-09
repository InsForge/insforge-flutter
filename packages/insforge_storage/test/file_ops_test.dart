// packages/insforge_storage/test/file_ops_test.dart
import 'dart:typed_data';

import 'package:insforge_core/insforge_core.dart';
import 'package:insforge_storage/insforge_storage.dart';
import 'package:test/test.dart';

import '_recording_adapter.dart';

InsforgeHttpClient _client(RecordingAdapter adapter) {
  final client = InsforgeHttpClient(
    baseUrl: 'https://x.insforge.app',
    anonKey: 'anon',
    apiKey: 'test-key',
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  test('download GETs with responseType bytes and returns a Uint8List',
      () async {
    final adapter = RecordingAdapter(
      responseBody: 'BINARYDATA',
      rawBody: true,
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    final bytes = await api.download('users/me.png');

    final req = adapter.single;
    expect(req.method, 'GET');
    expect(req.path, '/api/storage/buckets/avatars/objects/users/me.png');
    expect(bytes, isA<Uint8List>());
    expect(bytes, isNotEmpty);
  });

  test('list parses the data array and sends query params', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'bucket': 'avatars',
            'key': 'users/a.jpg',
            'size': 100,
            'mimeType': 'image/jpeg',
            'uploadedAt': '2024-01-15T10:30:00Z',
            'url': '/api/storage/buckets/avatars/objects/users/a.jpg',
          },
          <String, dynamic>{
            'bucket': 'avatars',
            'key': 'users/b.png',
            'size': 200,
            'mimeType': 'image/png',
            'uploadedAt': '2024-01-16T11:00:00Z',
            'url': '/api/storage/buckets/avatars/objects/users/b.png',
          },
        ],
        'pagination': <String, dynamic>{'offset': 0, 'limit': 100, 'total': 2},
      },
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    final files =
        await api.list(prefix: 'users/', limit: 50, offset: 10, search: 'a');

    final req = adapter.single;
    expect(req.method, 'GET');
    expect(req.path, '/api/storage/buckets/avatars/objects');
    expect(req.queryParameters['prefix'], 'users/');
    expect(req.queryParameters['limit'], '50');
    expect(req.queryParameters['offset'], '10');
    expect(req.queryParameters['search'], 'a');
    expect(files, hasLength(2));
    expect(files.first.key, 'users/a.jpg');
  });

  test('list omits null query params', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{'data': <dynamic>[]},
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.list();

    expect(adapter.single.queryParameters, isEmpty);
  });

  test('delete(path) issues a single DELETE', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{'message': 'Object deleted successfully'},
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.delete('users/me.png');

    final req = adapter.single;
    expect(req.method, 'DELETE');
    expect(req.path, '/api/storage/buckets/avatars/objects/users/me.png');
  });

  test('deleteAll(paths) DELETEs each path', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{'message': 'ok'},
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.deleteAll(<String>['a.png', 'b.png', 'c.png']);

    expect(adapter.requests, hasLength(3));
    expect(
      adapter.requests.map((CapturedRequest r) => r.path).toList(),
      <String>[
        '/api/storage/buckets/avatars/objects/a.png',
        '/api/storage/buckets/avatars/objects/b.png',
        '/api/storage/buckets/avatars/objects/c.png',
      ],
    );
  });

  test('getPublicUrl builds the {baseUrl}/.../objects/{path} string', () {
    final adapter = RecordingAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    expect(
      api.getPublicUrl('users/me.png'),
      'https://x.insforge.app/api/storage/buckets/avatars/objects/users/me.png',
    );
  });
}
