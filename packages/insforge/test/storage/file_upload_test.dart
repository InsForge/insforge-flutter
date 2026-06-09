// packages/insforge_storage/test/file_upload_test.dart
import 'dart:typed_data';

import 'package:insforge/insforge.dart';
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

RecordingAdapter _storedFileAdapter() => RecordingAdapter(
      responseBody: <String, dynamic>{
        'bucket': 'avatars',
        'key': 'users/me.png',
        'size': 1234,
        'mimeType': 'image/png',
        'uploadedAt': '2024-01-15T10:30:00Z',
        'url': '/api/storage/buckets/avatars/objects/users/me.png',
      },
    );

void main() {
  test('upload PUTs multipart with a file field and x-api-key, no x-upsert',
      () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    final result = await api.upload(
      'users/me.png',
      Uint8List.fromList(<int>[1, 2, 3, 4]),
    );

    final req = adapter.single;
    expect(req.method, 'PUT');
    expect(req.path, '/api/storage/buckets/avatars/objects/users/me.png');
    expect(req.isFormData, isTrue);
    expect(req.hasFileField, isTrue);
    expect(req.formFileFieldNames, <String>['file']);
    expect(req.headers['x-api-key'], 'test-key');
    expect(req.headers.containsKey('x-upsert'), isFalse);
    expect(result.key, 'users/me.png');
    expect(result.bucket, 'avatars');
  });

  test('upload sets x-upsert:true when upsert is requested', () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.upload(
      'users/me.png',
      Uint8List.fromList(<int>[1, 2, 3]),
      upsert: true,
    );

    expect(adapter.single.headers['x-upsert'], 'true');
  });

  test('uploadAutoKey POSTs multipart to /objects (no key in path)', () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.uploadAutoKey(
      'photo.png',
      Uint8List.fromList(<int>[9, 9, 9]),
    );

    final req = adapter.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/storage/buckets/avatars/objects');
    expect(req.isFormData, isTrue);
    expect(req.hasFileField, isTrue);
  });

  test('from() returns the same cached StorageFileApi per bucket', () {
    final adapter = _storedFileAdapter();
    final storage = StorageClient(_client(adapter));
    expect(identical(storage.from('avatars'), storage.from('avatars')), isTrue);
    expect(identical(storage.from('avatars'), storage.from('docs')), isFalse);
  });
}
