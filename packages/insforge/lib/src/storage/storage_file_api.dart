// packages/insforge_storage/lib/src/storage_file_api.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:insforge/insforge.dart';

/// Operations on the objects of a single bucket. Obtain one via
/// [StorageClient.from].
class StorageFileApi {
  StorageFileApi(this._http, this.bucket);

  final InsforgeHttpClient _http;

  /// The bucket these operations target.
  final String bucket;

  String get _bucketPath => '/api/storage/buckets/$bucket';

  /// The last `/`-separated segment of [path] (used as the multipart filename).
  static String _lastSegment(String path) {
    final i = path.lastIndexOf('/');
    return i >= 0 ? path.substring(i + 1) : path;
  }

  /// Builds a single-part `FormData` whose `file` field carries [bytes] with
  /// the given [filename] and [contentType].
  static FormData _fileFormData(
    Uint8List bytes,
    String filename,
    String contentType,
  ) {
    return FormData()
      ..files.add(
        MapEntry<String, MultipartFile>(
          'file',
          MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ),
        ),
      );
  }

  // ----- upload -----

  /// Uploads [bytes] to [path] (a specific key) via a multipart PUT.
  ///
  /// [contentType] is inferred from the extension when omitted. Set [upsert]
  /// to overwrite an existing object (`x-upsert: true`).
  Future<StoredFile> upload(
    String path,
    Uint8List bytes, {
    String? contentType,
    bool upsert = false,
    Map<String, dynamic>? metadata,
  }) async {
    final resolved = contentType ?? contentTypeForFilename(path);
    final form = _fileFormData(bytes, _lastSegment(path), resolved);
    final response = await _http.request<dynamic>(
      'PUT',
      '$_bucketPath/objects/$path',
      data: form,
      headers: <String, String>{if (upsert) 'x-upsert': 'true'},
    );
    return StoredFile.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  /// Uploads [bytes] with a server-generated key via a multipart POST.
  ///
  /// [filename] is used for content-type inference and key generation.
  Future<StoredFile> uploadAutoKey(
    String filename,
    Uint8List bytes, {
    String? contentType,
    bool upsert = false,
    Map<String, dynamic>? metadata,
  }) async {
    final resolved = contentType ?? contentTypeForFilename(filename);
    final form = _fileFormData(bytes, _lastSegment(filename), resolved);
    final response = await _http.request<dynamic>(
      'POST',
      '$_bucketPath/objects',
      data: form,
      headers: <String, String>{if (upsert) 'x-upsert': 'true'},
    );
    return StoredFile.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  // ----- download / list / delete / public url -----

  /// Downloads the object at [path] and returns its raw bytes.
  Future<Uint8List> download(String path) async {
    final response = await _http.request<List<int>>(
      'GET',
      '$_bucketPath/objects/$path',
      responseType: ResponseType.bytes,
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  /// Lists objects in the bucket, optionally filtered by [prefix]/[search] and
  /// paginated with [limit]/[offset]. Null parameters are omitted.
  Future<List<StoredFile>> list({
    String? prefix,
    int? limit,
    int? offset,
    String? search,
  }) async {
    final query = <String, dynamic>{
      if (prefix != null) 'prefix': prefix,
      if (limit != null) 'limit': '$limit',
      if (offset != null) 'offset': '$offset',
      if (search != null) 'search': search,
    };
    final response = await _http.request<dynamic>(
      'GET',
      '$_bucketPath/objects',
      queryParameters: query.isEmpty ? null : query,
    );
    final data = response.data;
    final raw = data is Map<String, dynamic> ? data['data'] : data;
    if (raw is List) {
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> e) =>
                StoredFile.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    }
    return <StoredFile>[];
  }

  /// Deletes the object at [path].
  Future<void> delete(String path) async {
    await _http.request<dynamic>('DELETE', '$_bucketPath/objects/$path');
  }

  /// Deletes every object in [paths] (the API has no batch-delete endpoint).
  Future<void> deleteAll(List<String> paths) async {
    for (final path in paths) {
      await delete(path);
    }
  }

  /// Builds the public download URL for [path] from the configured base URL.
  String getPublicUrl(String path) {
    return '${_http.baseUrl}$_bucketPath/objects/$path';
  }

  // ----- strategy flow -----

  /// Requests an [UploadStrategy] for [filename] (direct or presigned).
  Future<UploadStrategy> getUploadStrategy(
    String filename, {
    String? contentType,
    int? size,
  }) async {
    final response = await _http.request<dynamic>(
      'POST',
      '$_bucketPath/upload-strategy',
      data: <String, dynamic>{
        'filename': filename,
        if (contentType != null) 'contentType': contentType,
        if (size != null) 'size': size,
      },
    );
    return UploadStrategy.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  /// Requests a [DownloadStrategy] for the object at [path].
  ///
  /// The server auto-calculates presigned expiry from bucket visibility and
  /// accepts no body; [expiresIn] is reserved for forward-compatibility and is
  /// not transmitted.
  Future<DownloadStrategy> getDownloadStrategy(
    String path, {
    int? expiresIn,
  }) async {
    final response = await _http.request<dynamic>(
      'GET',
      '$_bucketPath/download-strategy/objects/$path',
    );
    return DownloadStrategy.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  /// Confirms a presigned upload of [objectKey], returning the [StoredFile].
  Future<StoredFile> confirmUpload(
    String objectKey, {
    required int size,
    String? contentType,
    String? etag,
  }) async {
    final response = await _http.request<dynamic>(
      'POST',
      '$_bucketPath/objects/$objectKey/confirm-upload',
      data: <String, dynamic>{
        'size': size,
        if (contentType != null) 'contentType': contentType,
        if (etag != null) 'etag': etag,
      },
    );
    return StoredFile.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  // ----- large / presigned upload -----

  /// Uploads [bytes] using the server-selected strategy.
  ///
  /// For a `presigned` strategy, POSTs a multipart body to the S3 presigned
  /// URL through a SEPARATE [Dio] (`presignedDio ?? Dio()`) that carries no
  /// `Authorization` header — S3 rejects a Bearer token. The `strategy.fields`
  /// are appended FIRST and the `file` part LAST (required by S3 presigned
  /// POST). When `strategy.confirmRequired`, the upload is confirmed via
  /// [confirmUpload]. For a `direct` strategy, falls back to [upload].
  Future<StoredFile> uploadLarge(
    String path,
    Uint8List bytes, {
    String? contentType,
    Dio? presignedDio,
  }) async {
    final resolved = contentType ?? contentTypeForFilename(path);
    final strategy = await getUploadStrategy(
      _lastSegment(path),
      contentType: resolved,
      size: bytes.length,
    );

    if (strategy.method != 'presigned') {
      return upload(path, bytes, contentType: resolved);
    }

    // Build the S3 presigned POST body: fields FIRST, file LAST.
    final form = FormData();
    strategy.fields?.forEach((String key, String value) {
      form.fields.add(MapEntry<String, String>(key, value));
    });
    form.files.add(
      MapEntry<String, MultipartFile>(
        'file',
        MultipartFile.fromBytes(
          bytes,
          filename: strategy.key,
          contentType: MediaType.parse(resolved),
        ),
      ),
    );

    final dio = presignedDio ?? Dio();
    await dio.post<dynamic>(strategy.uploadUrl, data: form);

    if (strategy.confirmRequired) {
      return confirmUpload(
        strategy.key,
        size: bytes.length,
        contentType: resolved,
      );
    }

    // No confirmation required: synthesize a StoredFile from the strategy.
    return StoredFile(
      bucket: bucket,
      key: strategy.key,
      size: bytes.length,
      mimeType: resolved,
      uploadedAt: DateTime.now().toUtc(),
      url: getPublicUrl(strategy.key),
    );
  }
}
