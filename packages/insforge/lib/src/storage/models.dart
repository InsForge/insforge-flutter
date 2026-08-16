// packages/insforge_storage/lib/src/models.dart
import 'package:insforge/insforge.dart';

/// Metadata for a stored object, as returned by the storage API.
class StoredFile {
  const StoredFile({
    required this.bucket,
    required this.key,
    required this.size,
    required this.uploadedAt,
    required this.url,
    this.mimeType,
  });

  /// Name of the bucket containing the object.
  final String bucket;

  /// Unique key identifying the object within the bucket.
  final String key;

  /// Size of the file in bytes.
  final int size;

  /// MIME type of the file, when the server reports one.
  final String? mimeType;

  /// When the file was uploaded (UTC), parsed tolerant of date formats.
  final DateTime? uploadedAt;

  /// Relative or absolute URL to download the file.
  final String url;

  factory StoredFile.fromJson(Map<String, dynamic> json) {
    final rawSize = json['size'];
    return StoredFile(
      bucket: (json['bucket'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      size: rawSize is int ? rawSize : int.tryParse('$rawSize') ?? 0,
      mimeType: json['mimeType']?.toString(),
      uploadedAt: parseInsforgeDate(json['uploadedAt']?.toString()),
      url: (json['url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'bucket': bucket,
        'key': key,
        'size': size,
        if (mimeType != null) 'mimeType': mimeType,
        if (uploadedAt != null) 'uploadedAt': uploadedAt!.toIso8601String(),
        'url': url,
      };
}

/// Information about a bucket: its [name] and whether it is publicly readable.
class BucketInfo {
  const BucketInfo({required this.name, this.isPublic = true});

  /// The bucket name/id.
  final String name;

  /// Whether the bucket is publicly accessible.
  final bool isPublic;

  /// Tolerant parser: accepts either a bare string name (the list-buckets
  /// wire shape, `{buckets: ["a","b"]}`) or an object carrying
  /// `name`/`bucketName` and `isPublic`. When only a name is available,
  /// [isPublic] defaults to `true` (the server's create default).
  factory BucketInfo.fromJson(Object? json) {
    if (json is String) {
      return BucketInfo(name: json);
    }
    if (json is Map) {
      final map = Map<String, dynamic>.from(json);
      final name = (map['name'] ?? map['bucketName'] ?? '').toString();
      final isPublic = map['isPublic'];
      return BucketInfo(
        name: name,
        isPublic: isPublic is bool ? isPublic : true,
      );
    }
    return BucketInfo(name: json?.toString() ?? '');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'isPublic': isPublic,
      };
}

/// How to upload an object: `direct` (POST/PUT to InsForge) or `presigned`
/// (POST to an S3 presigned URL, then confirm).
class UploadStrategy {
  const UploadStrategy({
    required this.method,
    required this.uploadUrl,
    required this.key,
    required this.confirmRequired,
    this.fields,
    this.confirmUrl,
    this.expiresAt,
  });

  /// `direct` for local storage, `presigned` for S3.
  final String method;

  /// URL to upload the file to.
  final String uploadUrl;

  /// Form fields for a presigned POST (S3 only); null for direct uploads.
  final Map<String, String>? fields;

  /// Generated unique key for the file.
  final String key;

  /// Whether [confirmUrl] must be called after a successful upload.
  final bool confirmRequired;

  /// URL to confirm the upload, present when [confirmRequired] is true.
  final String? confirmUrl;

  /// Expiration of the presigned URL (S3 only).
  final DateTime? expiresAt;

  factory UploadStrategy.fromJson(Map<String, dynamic> json) {
    final rawFields = json['fields'];
    return UploadStrategy(
      method: (json['method'] ?? 'direct').toString(),
      uploadUrl: (json['uploadUrl'] ?? '').toString(),
      fields: rawFields is Map
          ? rawFields.map(
              (Object? k, Object? v) => MapEntry<String, String>('$k', '$v'),
            )
          : null,
      key: (json['key'] ?? '').toString(),
      confirmRequired: json['confirmRequired'] == true,
      confirmUrl: json['confirmUrl']?.toString(),
      expiresAt: parseInsforgeDate(json['expiresAt']?.toString()),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': method,
        'uploadUrl': uploadUrl,
        if (fields != null) 'fields': fields,
        'key': key,
        'confirmRequired': confirmRequired,
        if (confirmUrl != null) 'confirmUrl': confirmUrl,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };
}

/// How to download an object: `direct` (a plain URL) or `presigned`
/// (a signed URL with an expiry and optional headers).
class DownloadStrategy {
  const DownloadStrategy({
    required this.method,
    required this.url,
    this.expiresAt,
    this.headers,
  });

  /// `direct` or `presigned`.
  final String method;

  /// URL to download the file from.
  final String url;

  /// Expiration of a presigned URL, when present.
  final DateTime? expiresAt;

  /// Optional headers to include in the download request.
  final Map<String, String>? headers;

  factory DownloadStrategy.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    return DownloadStrategy(
      method: (json['method'] ?? 'direct').toString(),
      url: (json['url'] ?? '').toString(),
      expiresAt: parseInsforgeDate(json['expiresAt']?.toString()),
      headers: rawHeaders is Map
          ? rawHeaders.map(
              (Object? k, Object? v) => MapEntry<String, String>('$k', '$v'),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': method,
        'url': url,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (headers != null) 'headers': headers,
      };
}

/// Options for an upload: an explicit [contentType] (otherwise inferred from
/// the filename extension) and optional [metadata].
class FileOptions {
  const FileOptions({
    this.contentType,
    @Deprecated(
      'Uploads follow standard PUT semantics and always replace an existing '
      'object; this flag is a no-op and will be removed in a future release.',
    )
    this.upsert = false,
    this.metadata,
  });

  final String? contentType;

  /// No-op: uploads follow standard PUT semantics and always replace an
  /// existing object.
  @Deprecated(
    'Uploads follow standard PUT semantics and always replace an existing '
    'object; this flag is a no-op and will be removed in a future release.',
  )
  final bool upsert;

  final Map<String, dynamic>? metadata;
}
