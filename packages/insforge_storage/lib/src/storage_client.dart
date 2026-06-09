// packages/insforge_storage/lib/src/storage_client.dart
import 'package:insforge_core/insforge_core.dart';

import 'models.dart';
import 'storage_file_api.dart';

/// Entry point for InsForge storage: bucket administration plus per-bucket
/// file operations via [from].
///
/// Wraps a shared [InsforgeHttpClient]. Storage authenticates with the
/// `x-api-key` header, so the client MUST be constructed with an `apiKey`
/// (the umbrella package passes the project key).
class StorageClient {
  StorageClient(this._http);

  final InsforgeHttpClient _http;

  static const String _bucketsPath = '/api/storage/buckets';

  final Map<String, StorageFileApi> _bucketCache = <String, StorageFileApi>{};

  /// Returns the [StorageFileApi] for [bucket], cached per bucket name.
  StorageFileApi from(String bucket) {
    return _bucketCache.putIfAbsent(
      bucket,
      () => StorageFileApi(_http, bucket),
    );
  }

  // ----- bucket administration -----

  /// Lists all buckets. The server returns bucket names; each is wrapped in a
  /// [BucketInfo] (with `isPublic` defaulting to true when unknown).
  Future<List<BucketInfo>> listBuckets() async {
    final response = await _http.request<dynamic>('GET', _bucketsPath);
    final data = response.data;
    final raw = data is Map<String, dynamic> ? data['buckets'] : data;
    if (raw is List) {
      return raw.map(BucketInfo.fromJson).toList();
    }
    return <BucketInfo>[];
  }

  /// Creates a bucket named [name]. Public by default.
  Future<void> createBucket(String name, {bool isPublic = true}) async {
    await _http.request<dynamic>(
      'POST',
      _bucketsPath,
      data: <String, dynamic>{'bucketName': name, 'isPublic': isPublic},
    );
  }

  /// Updates a bucket's visibility.
  Future<void> updateBucket(String name, {required bool isPublic}) async {
    await _http.request<dynamic>(
      'PATCH',
      '$_bucketsPath/$name',
      data: <String, dynamic>{'isPublic': isPublic},
    );
  }

  /// Deletes a bucket and all of its objects.
  Future<void> deleteBucket(String name) async {
    await _http.request<dynamic>('DELETE', '$_bucketsPath/$name');
  }
}
