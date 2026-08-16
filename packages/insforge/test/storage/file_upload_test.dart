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

  test('upload treats the deprecated upsert flag as a no-op (no x-upsert)',
      () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.upload(
      'users/me.png',
      Uint8List.fromList(<int>[1, 2, 3]),
      // ignore: deprecated_member_use_from_same_package
      upsert: true,
    );

    expect(adapter.single.headers.containsKey('x-upsert'), isFalse);
  });

  test('uploadAutoKey mints a unique key client-side and PUTs to it', () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.uploadAutoKey(
      'photo.png',
      Uint8List.fromList(<int>[9, 9, 9]),
    );

    final req = adapter.single;
    expect(req.method, 'PUT');
    // Client-generated key: sanitized base + timestamp + random, keeping the
    // extension — the backend no longer mints keys.
    expect(
      req.path,
      matches(
        RegExp(r'^/api/storage/buckets/avatars/objects/'
            r'photo-\d+-[a-z0-9]{6}\.png$'),
      ),
    );
    expect(req.isFormData, isTrue);
    expect(req.hasFileField, isTrue);
  });

  test('uploadAutoKey sanitizes the filename base and keeps the extension',
      () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.uploadAutoKey(
      'my photo (1).png',
      Uint8List.fromList(<int>[9]),
    );

    expect(
      adapter.single.path,
      matches(
        RegExp(r'^/api/storage/buckets/avatars/objects/'
            r'my-photo--1--\d+-[a-z0-9]{6}\.png$'),
      ),
    );
  });

  test('uploadAutoKey handles filenames without an extension', () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.uploadAutoKey('README', Uint8List.fromList(<int>[9]));

    expect(
      adapter.single.path,
      matches(
        RegExp(r'^/api/storage/buckets/avatars/objects/'
            r'README-\d+-[a-z0-9]{6}$'),
      ),
    );
  });

  test('uploadAutoKey falls back to a "file" base for an empty filename',
      () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.uploadAutoKey('', Uint8List.fromList(<int>[9]));

    expect(
      adapter.single.path,
      matches(
        RegExp(r'^/api/storage/buckets/avatars/objects/'
            r'file-\d+-[a-z0-9]{6}$'),
      ),
    );
  });

  test('uploadAutoKey generates distinct keys for the same filename', () async {
    final adapter = _storedFileAdapter();
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.uploadAutoKey('photo.png', Uint8List.fromList(<int>[1]));
    await api.uploadAutoKey('photo.png', Uint8List.fromList(<int>[2]));

    expect(adapter.requests, hasLength(2));
    expect(adapter.requests[0].path, isNot(adapter.requests[1].path));
  });

  test('from() returns the same cached StorageFileApi per bucket', () {
    final adapter = _storedFileAdapter();
    final storage = StorageClient(_client(adapter));
    expect(identical(storage.from('avatars'), storage.from('avatars')), isTrue);
    expect(identical(storage.from('avatars'), storage.from('docs')), isFalse);
  });
}
