// packages/insforge_storage/test/upload_large_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
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
  test('presigned uploadLarge uses a no-auth Dio, file LAST, then confirms',
      () async {
    // The MAIN client returns a presigned strategy, then a StoredFile on
    // confirm. Sequence its responses across the two calls.
    final mainAdapter = _SequencedAdapter(<Object>[
      <String, dynamic>{
        'method': 'presigned',
        'uploadUrl': 'https://s3-bucket.amazonaws.com/',
        'fields': <String, dynamic>{
          'key': 'app/avatars/profile-1234.jpg',
          'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
          'Policy': 'eyJ',
          'X-Amz-Signature': 'abc123',
        },
        'key': 'profile-1234.jpg',
        'confirmRequired': true,
        'confirmUrl':
            '/api/storage/buckets/avatars/objects/profile-1234.jpg/confirm-upload',
        'expiresAt': '2025-09-05T01:00:00Z',
      },
      <String, dynamic>{
        'bucket': 'avatars',
        'key': 'profile-1234.jpg',
        'size': 4,
        'mimeType': 'image/jpeg',
        'uploadedAt': '2024-01-21T10:30:00Z',
        'url': '/api/storage/buckets/avatars/objects/profile-1234.jpg',
      },
    ]);
    final api = StorageClient(_client(mainAdapter)).from('avatars');

    // A SEPARATE Dio whose adapter records the S3 POST. The test asserts no
    // Authorization header and that `file` is the last FormData part.
    final s3Adapter = RecordingAdapter(statusCode: 204, responseBody: null);
    final s3Dio = Dio()..httpClientAdapter = s3Adapter;

    final result = await api.uploadLarge(
      'profile-1234.jpg',
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      contentType: 'image/jpeg',
      presignedDio: s3Dio,
    );

    // 1) The S3 POST went through the injected (separate) Dio.
    final s3Req = s3Adapter.single;
    expect(s3Req.method, 'POST');
    expect(s3Req.isFormData, isTrue);

    // 2) No Authorization header on the S3 request.
    expect(s3Req.headers.containsKey('Authorization'), isFalse);

    // 3) The `file` part is LAST: every presigned field name precedes it.
    expect(s3Req.formFileFieldNames, <String>['file']);
    expect(
      s3Req.formFieldNames,
      <String>['key', 'X-Amz-Algorithm', 'Policy', 'X-Amz-Signature'],
    );

    // 4) The MAIN client got the strategy POST then the confirm POST.
    expect(
        mainAdapter.requests.map((CapturedRequest r) => r.path).toList(),
        <String>[
          '/api/storage/buckets/avatars/upload-strategy',
          '/api/storage/buckets/avatars/objects/profile-1234.jpg/confirm-upload',
        ]);
    expect(result.key, 'profile-1234.jpg');
  });

  test('direct strategy falls back to a plain multipart upload', () async {
    final mainAdapter = _SequencedAdapter(<Object>[
      <String, dynamic>{
        'method': 'direct',
        'uploadUrl': '/api/storage/buckets/avatars/objects/x.png',
        'key': 'x.png',
        'confirmRequired': false,
      },
      <String, dynamic>{
        'bucket': 'avatars',
        'key': 'x.png',
        'size': 3,
        'mimeType': 'image/png',
        'uploadedAt': '2024-01-21T10:30:00Z',
        'url': '/api/storage/buckets/avatars/objects/x.png',
      },
    ]);
    final api = StorageClient(_client(mainAdapter)).from('avatars');

    final s3Adapter = RecordingAdapter(statusCode: 204, responseBody: null);
    final s3Dio = Dio()..httpClientAdapter = s3Adapter;

    final result = await api.uploadLarge(
      'x.png',
      Uint8List.fromList(<int>[7, 8, 9]),
      presignedDio: s3Dio,
    );

    // The separate Dio is NOT used for a direct strategy.
    expect(s3Adapter.requests, isEmpty);
    // The main client did the strategy POST then a multipart PUT upload.
    expect(mainAdapter.requests, hasLength(2));
    expect(mainAdapter.requests[1].method, 'PUT');
    expect(mainAdapter.requests[1].isFormData, isTrue);
    expect(result.key, 'x.png');
  });
}

/// A RecordingAdapter that returns a different JSON body for each call, in
/// order. Reuses the shared [RecordingAdapter]'s request-capture and FormData
/// introspection by delegating to a fresh per-call instance and accumulating
/// its captured requests here.
class _SequencedAdapter extends RecordingAdapter {
  _SequencedAdapter(this._bodies);

  final List<Object> _bodies;
  int _index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Pick the next canned body (clamp to the last once exhausted).
    final body = _bodies[_index < _bodies.length ? _index : _bodies.length - 1];
    _index++;
    final delegate = RecordingAdapter(responseBody: body);
    final resp = await delegate.fetch(options, requestStream, cancelFuture);
    // Accumulate the captured request onto THIS adapter's list.
    requests.addAll(delegate.requests);
    return resp;
  }
}
