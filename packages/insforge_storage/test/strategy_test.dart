// packages/insforge_storage/test/strategy_test.dart
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
  test('getUploadStrategy POSTs filename/contentType/size and parses presigned',
      () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{
        'method': 'presigned',
        'uploadUrl': 'https://s3-bucket.amazonaws.com/',
        'fields': <String, dynamic>{'key': 'app/profile.jpg'},
        'key': 'profile-1234.jpg',
        'confirmRequired': true,
        'confirmUrl':
            '/api/storage/buckets/avatars/objects/profile-1234.jpg/confirm-upload',
        'expiresAt': '2025-09-05T01:00:00Z',
      },
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    final strategy = await api.getUploadStrategy(
      'profile.jpg',
      contentType: 'image/jpeg',
      size: 102400,
    );

    final req = adapter.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/storage/buckets/avatars/upload-strategy');
    expect(req.body, <String, dynamic>{
      'filename': 'profile.jpg',
      'contentType': 'image/jpeg',
      'size': 102400,
    });
    expect(strategy.method, 'presigned');
    expect(strategy.confirmRequired, isTrue);
    expect(strategy.key, 'profile-1234.jpg');
  });

  test('getUploadStrategy omits null contentType/size', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{
        'method': 'direct',
        'uploadUrl': '/api/storage/buckets/avatars/objects/x.jpg',
        'key': 'x.jpg',
        'confirmRequired': false,
      },
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    await api.getUploadStrategy('x.jpg');

    expect(adapter.single.body, <String, dynamic>{'filename': 'x.jpg'});
  });

  test('getDownloadStrategy GETs the canonical download-strategy path',
      () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{
        'method': 'presigned',
        'url': 'https://s3-bucket.s3.amazonaws.com/x?X-Amz-Signature=abc',
        'expiresAt': '2025-09-05T01:00:00Z',
      },
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    final strategy = await api.getDownloadStrategy('users/me.png');

    final req = adapter.single;
    expect(req.method, 'GET');
    expect(
      req.path,
      '/api/storage/buckets/avatars/download-strategy/objects/users/me.png',
    );
    expect(strategy.method, 'presigned');
    expect(strategy.expiresAt, isNotNull);
  });

  test('confirmUpload POSTs size/contentType/etag and parses StoredFile',
      () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{
        'bucket': 'avatars',
        'key': 'profile-1234.jpg',
        'size': 102400,
        'mimeType': 'image/jpeg',
        'uploadedAt': '2024-01-21T10:30:00Z',
        'url': '/api/storage/buckets/avatars/objects/profile-1234.jpg',
      },
    );
    final api = StorageClient(_client(adapter)).from('avatars');

    final file = await api.confirmUpload(
      'profile-1234.jpg',
      size: 102400,
      contentType: 'image/jpeg',
      etag: '9bb58f26192e4ba00f01e2e7b136bbd8',
    );

    final req = adapter.single;
    expect(req.method, 'POST');
    expect(
      req.path,
      '/api/storage/buckets/avatars/objects/profile-1234.jpg/confirm-upload',
    );
    expect(req.body, <String, dynamic>{
      'size': 102400,
      'contentType': 'image/jpeg',
      'etag': '9bb58f26192e4ba00f01e2e7b136bbd8',
    });
    expect(file.key, 'profile-1234.jpg');
    expect(file.size, 102400);
  });
}
