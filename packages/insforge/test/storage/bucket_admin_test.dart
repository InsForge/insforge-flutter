// packages/insforge_storage/test/bucket_admin_test.dart
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

void main() {
  test('listBuckets parses the {buckets:[...]} string array', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{
        'buckets': <String>['avatars', 'documents', 'uploads'],
      },
    );
    final storage = StorageClient(_client(adapter));

    final buckets = await storage.listBuckets();

    final req = adapter.single;
    expect(req.method, 'GET');
    expect(req.path, '/api/storage/buckets');
    expect(req.headers['x-api-key'], 'test-key');
    expect(
      buckets.map((BucketInfo b) => b.name).toList(),
      <String>['avatars', 'documents', 'uploads'],
    );
    expect(buckets.first.isPublic, isTrue);
  });

  test('createBucket POSTs {bucketName, isPublic}', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{
        'message': 'Bucket created successfully',
        'bucketName': 'avatars',
      },
    );
    final storage = StorageClient(_client(adapter));

    await storage.createBucket('avatars', isPublic: false);

    final req = adapter.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/storage/buckets');
    expect(req.body, <String, dynamic>{
      'bucketName': 'avatars',
      'isPublic': false,
    });
    expect(req.headers['x-api-key'], 'test-key');
  });

  test('createBucket defaults isPublic to true', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{'message': 'ok'},
    );
    final storage = StorageClient(_client(adapter));

    await storage.createBucket('avatars');

    expect(adapter.single.body, <String, dynamic>{
      'bucketName': 'avatars',
      'isPublic': true,
    });
  });

  test('updateBucket PATCHes {isPublic} at the bucket path', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{
        'message': 'Bucket visibility updated',
        'bucket': 'avatars',
        'isPublic': true,
      },
    );
    final storage = StorageClient(_client(adapter));

    await storage.updateBucket('avatars', isPublic: true);

    final req = adapter.single;
    expect(req.method, 'PATCH');
    expect(req.path, '/api/storage/buckets/avatars');
    expect(req.body, <String, dynamic>{'isPublic': true});
  });

  test('deleteBucket DELETEs the bucket path', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{'message': 'Bucket deleted successfully'},
    );
    final storage = StorageClient(_client(adapter));

    await storage.deleteBucket('avatars');

    final req = adapter.single;
    expect(req.method, 'DELETE');
    expect(req.path, '/api/storage/buckets/avatars');
  });
}
