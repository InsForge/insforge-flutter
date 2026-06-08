# InsForge Flutter SDK — Plan 4: `insforge_storage` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart `insforge_storage` package: bucket-based object storage over the InsForge storage REST API. It exposes `StorageClient(http)` with bucket admin (`listBuckets`, `createBucket`, `updateBucket`, `deleteBucket`) and `from(bucket) → StorageFileApi`; a per-bucket `StorageFileApi` covering direct multipart upload (`upload`/`uploadAutoKey`), `download` (raw bytes), `list`, `delete`, public-URL construction, the upload/download **strategy** flow (`getUploadStrategy`/`getDownloadStrategy`/`confirmUpload`), and a presigned-S3 `uploadLarge` that uploads through a **separate no-auth Dio** with the `file` field last. Plus hand-written models and a content-type-from-extension helper.

**Architecture:** `insforge_storage` depends only on `insforge_core` (built in Plan 1) and reuses its `InsforgeHttpClient`, exception hierarchy, options, and `parseInsforgeDate`. Storage endpoints authenticate with the `x-api-key` header, which `InsforgeHttpClient` only sends when constructed with `apiKey`; the umbrella (Plan 7) passes the project's `apiKey`, and tests construct `InsforgeHttpClient(baseUrl: ..., anonKey: ..., apiKey: 'test-key')`. All requests go through `InsforgeHttpClient.request`, so auth-header injection, single-flight 401 refresh, and error mapping are inherited for free. The presigned upload step is the one exception: S3 presigned POSTs must NOT carry an `Authorization` header (S3 rejects "Unsupported Authorization Type"), so `uploadLarge` posts through a caller-injectable plain `Dio` (`presignedDio ?? Dio()`) with no interceptors. Models are hand-written `fromJson`/`toJson` (no build_runner), tolerant of snake_case ↔ camelCase. No Flutter dependency.

**Tech Stack:** Dart ≥ 3.5 (pub workspaces), `dio` ^5.7.0, `meta` ^1.15.0, `http_parser` ^4.0.2 (for `MediaType` in multipart), `insforge_core` (path dependency); dev: `test`, `lints`, `http_mock_adapter` ^0.6.1.

**Prerequisite:** The Flutter SDK (which bundles Dart) must be installed and on `PATH` (`dart --version` must work). It is not currently installed on this machine — install it before executing. Plan 1 (`insforge_core`) must be complete and on disk at `packages/insforge_core`.

**Plan series:** This is plan 4 of 7. Earlier: 01 core, 02 auth, 03 database. Subsequent: 05 functions, 06 ai, 07 umbrella + sample. This plan appends `packages/insforge_storage` to the workspace member list created in Plan 1.

---

## File Structure

```
insforge-flutter/
├── pubspec.yaml                              # MODIFIED: append packages/insforge_storage to workspace
└── packages/
    └── insforge_storage/
        ├── pubspec.yaml
        ├── analysis_options.yaml             # includes root lints
        ├── lib/
        │   ├── insforge_storage.dart         # public exports
        │   └── src/
        │       ├── mime.dart                 # extension→MIME map + contentTypeForFilename
        │       ├── models.dart               # StoredFile/BucketInfo/UploadStrategy/DownloadStrategy/FileOptions
        │       ├── storage_file_api.dart     # StorageFileApi (per-bucket operations)
        │       └── storage_client.dart       # StorageClient (bucket admin + from())
        └── test/
            ├── _recording_adapter.dart       # shared FormData-aware RecordingAdapter test helper
            ├── mime_test.dart                # extension→MIME inference
            ├── models_test.dart              # fromJson/toJson for all models
            ├── bucket_admin_test.dart        # listBuckets / createBucket body / update / delete
            ├── file_upload_test.dart         # upload PUT multipart + x-upsert + x-api-key; uploadAutoKey POST
            ├── file_ops_test.dart            # download bytes / list / delete / getPublicUrl
            ├── strategy_test.dart            # getUploadStrategy / getDownloadStrategy / confirmUpload parsing
            └── upload_large_test.dart        # presigned no-auth Dio, file field LAST, then confirmUpload
```

---

## Task 1: Package scaffolding

**Files:**
- Create: `packages/insforge_storage/pubspec.yaml`
- Create: `packages/insforge_storage/analysis_options.yaml`
- Create: `packages/insforge_storage/lib/insforge_storage.dart`
- Modify: `pubspec.yaml` (workspace root)

- [ ] **Step 1: Create the package `pubspec.yaml`**

```yaml
# packages/insforge_storage/pubspec.yaml
name: insforge_storage
description: Bucket-based object storage (incl. S3 presigned upload/download) for the InsForge Flutter SDK.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.5.0

dependencies:
  dio: ^5.7.0
  meta: ^1.15.0
  http_parser: ^4.0.2
  insforge_core:
    path: ../insforge_core

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  http_mock_adapter: ^0.6.1
```

- [ ] **Step 2: Create the package-local `analysis_options.yaml`**

```yaml
# packages/insforge_storage/analysis_options.yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 3: Create a placeholder library export file**

```dart
// packages/insforge_storage/lib/insforge_storage.dart
/// Bucket-based object storage for the InsForge Flutter SDK.
library insforge_storage;

// Exports are added as each component lands in later tasks.
```

- [ ] **Step 4: Add the package to the workspace**

In the root `pubspec.yaml`, append the new package path to the `workspace:` list so it reads:

```yaml
# pubspec.yaml (root) — workspace section
workspace:
  - packages/insforge_core
  - packages/insforge_auth
  - packages/insforge_database
  - packages/insforge_storage
```

(If earlier plans' lines are not yet present, just ensure `packages/insforge_storage` is listed alongside `packages/insforge_core`.)

- [ ] **Step 5: Resolve dependencies**

Run: `dart pub get` (from repo root)
Expected: resolves the workspace including `insforge_storage`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/insforge_storage/pubspec.yaml packages/insforge_storage/analysis_options.yaml packages/insforge_storage/lib/insforge_storage.dart
git commit -m "feat(storage): add insforge_storage package skeleton"
```

---

## Task 2: Content-type-from-extension helper

**Files:**
- Create: `packages/insforge_storage/lib/src/mime.dart`
- Test: `packages/insforge_storage/test/mime_test.dart`
- Modify: `packages/insforge_storage/lib/insforge_storage.dart`

The map mirrors the Kotlin SDK's `CONTENT_TYPE_MAP`, scoped to the entries the design calls out. The lookup is case-insensitive on the extension and falls back to `application/octet-stream`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_storage/test/mime_test.dart
import 'package:insforge_storage/insforge_storage.dart';
import 'package:test/test.dart';

void main() {
  group('contentTypeForFilename', () {
    test('maps known image extensions', () {
      expect(contentTypeForFilename('a.jpg'), 'image/jpeg');
      expect(contentTypeForFilename('a.jpeg'), 'image/jpeg');
      expect(contentTypeForFilename('a.png'), 'image/png');
      expect(contentTypeForFilename('a.gif'), 'image/gif');
      expect(contentTypeForFilename('a.webp'), 'image/webp');
      expect(contentTypeForFilename('a.svg'), 'image/svg+xml');
    });

    test('maps documents, text, and video extensions', () {
      expect(contentTypeForFilename('doc.pdf'), 'application/pdf');
      expect(contentTypeForFilename('data.json'), 'application/json');
      expect(contentTypeForFilename('notes.txt'), 'text/plain');
      expect(contentTypeForFilename('clip.mp4'), 'video/mp4');
    });

    test('is case-insensitive on the extension', () {
      expect(contentTypeForFilename('PHOTO.JPG'), 'image/jpeg');
      expect(contentTypeForFilename('DOC.Pdf'), 'application/pdf');
    });

    test('handles nested paths (uses last segment + last dot)', () {
      expect(contentTypeForFilename('users/avatars/me.png'), 'image/png');
    });

    test('falls back to application/octet-stream', () {
      expect(contentTypeForFilename('archive.unknownext'), 'application/octet-stream');
      expect(contentTypeForFilename('noextension'), 'application/octet-stream');
      expect(contentTypeForFilename(''), 'application/octet-stream');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_storage && dart test test/mime_test.dart`
Expected: FAIL — `contentTypeForFilename` not defined.

- [ ] **Step 3: Write `mime.dart`**

```dart
// packages/insforge_storage/lib/src/mime.dart

/// Default content type used when an extension is unknown or absent.
const String defaultContentType = 'application/octet-stream';

/// Extension (lowercase, no dot) → MIME type. Mirrors the Kotlin SDK's map,
/// scoped to the types the Flutter SDK design enumerates.
const Map<String, String> _extensionToMime = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'pdf': 'application/pdf',
  'json': 'application/json',
  'txt': 'text/plain',
  'mp4': 'video/mp4',
};

/// Infers a MIME type from [filename]'s extension, falling back to
/// [defaultContentType] (`application/octet-stream`).
///
/// Uses the last path segment and the substring after its final `.`, matched
/// case-insensitively. Returns the fallback when there is no extension.
String contentTypeForFilename(String filename) {
  final lastSlash = filename.lastIndexOf('/');
  final segment =
      lastSlash >= 0 ? filename.substring(lastSlash + 1) : filename;
  final dot = segment.lastIndexOf('.');
  if (dot < 0 || dot == segment.length - 1) {
    return defaultContentType;
  }
  final ext = segment.substring(dot + 1).toLowerCase();
  return _extensionToMime[ext] ?? defaultContentType;
}
```

- [ ] **Step 4: Export it**

In `packages/insforge_storage/lib/insforge_storage.dart`, replace the trailing comment with:

```dart
export 'src/mime.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_storage && dart test test/mime_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_storage/lib/src/mime.dart packages/insforge_storage/lib/insforge_storage.dart packages/insforge_storage/test/mime_test.dart
git commit -m "feat(storage): add extension→MIME content-type helper"
```

---

## Task 3: Models

**Files:**
- Create: `packages/insforge_storage/lib/src/models.dart`
- Test: `packages/insforge_storage/test/models_test.dart`
- Modify: `packages/insforge_storage/lib/insforge_storage.dart`

Field names are confirmed against `storage.yaml`:
- `StoredFile`: `bucket`, `key`, `size` (int), `mimeType` (nullable), `uploadedAt` (ISO date-time → `parseInsforgeDate`), `url`.
- `BucketInfo`: `name`, `isPublic`. The list-buckets endpoint returns `{buckets: ["a","b"]}` (plain strings), so `BucketInfo.fromJson` is tolerant: it accepts either a bare string name or an object with `name`/`bucketName` + `isPublic`. When only a name is present, `isPublic` defaults to `true` (the server's create default).
- `UploadStrategy`: `method` (`direct`|`presigned`), `uploadUrl`, `fields` (`Map<String,String>?`), `key`, `confirmRequired` (bool), `confirmUrl?`, `expiresAt?` (→ `parseInsforgeDate`).
- `DownloadStrategy`: `method`, `url`, `expiresAt?`, `headers` (`Map<String,String>?`).
- `FileOptions`: `contentType?`, `upsert` (bool, default false), `metadata` (`Map?`).

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_storage/test/models_test.dart
import 'package:insforge_storage/insforge_storage.dart';
import 'package:test/test.dart';

void main() {
  group('StoredFile.fromJson', () {
    test('parses the storage.yaml object shape', () {
      final f = StoredFile.fromJson(<String, dynamic>{
        'bucket': 'avatars',
        'key': 'users/user123.jpg',
        'size': 102400,
        'mimeType': 'image/jpeg',
        'uploadedAt': '2024-01-15T10:30:00Z',
        'url': '/api/storage/buckets/avatars/objects/users/user123.jpg',
      });
      expect(f.bucket, 'avatars');
      expect(f.key, 'users/user123.jpg');
      expect(f.size, 102400);
      expect(f.mimeType, 'image/jpeg');
      expect(f.uploadedAt, isNotNull);
      expect(f.uploadedAt!.isUtc, isTrue);
      expect(f.uploadedAt!.year, 2024);
      expect(f.url, '/api/storage/buckets/avatars/objects/users/user123.jpg');
    });

    test('tolerates a missing/null mimeType', () {
      final f = StoredFile.fromJson(<String, dynamic>{
        'bucket': 'b',
        'key': 'k',
        'size': 0,
        'uploadedAt': '2024-01-15T10:30:00Z',
        'url': '/u',
      });
      expect(f.mimeType, isNull);
    });
  });

  group('BucketInfo.fromJson', () {
    test('parses a bare string name (list-buckets shape)', () {
      final b = BucketInfo.fromJson('avatars');
      expect(b.name, 'avatars');
      expect(b.isPublic, isTrue);
    });

    test('parses an object with name + isPublic', () {
      final b = BucketInfo.fromJson(<String, dynamic>{
        'name': 'docs',
        'isPublic': false,
      });
      expect(b.name, 'docs');
      expect(b.isPublic, isFalse);
    });

    test('accepts bucketName as an alias for name', () {
      final b = BucketInfo.fromJson(<String, dynamic>{
        'bucketName': 'uploads',
        'isPublic': true,
      });
      expect(b.name, 'uploads');
      expect(b.isPublic, isTrue);
    });
  });

  group('UploadStrategy.fromJson', () {
    test('parses the S3 presigned shape', () {
      final s = UploadStrategy.fromJson(<String, dynamic>{
        'method': 'presigned',
        'uploadUrl': 'https://s3-bucket.amazonaws.com/',
        'fields': <String, dynamic>{
          'key': 'app-key/avatars/profile.jpg',
          'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
        },
        'key': 'profile-1234.jpg',
        'confirmRequired': true,
        'confirmUrl':
            '/api/storage/buckets/avatars/objects/profile-1234.jpg/confirm-upload',
        'expiresAt': '2025-09-05T01:00:00Z',
      });
      expect(s.method, 'presigned');
      expect(s.uploadUrl, 'https://s3-bucket.amazonaws.com/');
      expect(s.fields!['X-Amz-Algorithm'], 'AWS4-HMAC-SHA256');
      expect(s.key, 'profile-1234.jpg');
      expect(s.confirmRequired, isTrue);
      expect(s.confirmUrl, contains('confirm-upload'));
      expect(s.expiresAt, isNotNull);
    });

    test('parses the local direct shape (no fields/confirm)', () {
      final s = UploadStrategy.fromJson(<String, dynamic>{
        'method': 'direct',
        'uploadUrl': '/api/storage/buckets/avatars/objects/profile-1234.jpg',
        'key': 'profile-1234.jpg',
        'confirmRequired': false,
      });
      expect(s.method, 'direct');
      expect(s.fields, isNull);
      expect(s.confirmRequired, isFalse);
      expect(s.confirmUrl, isNull);
      expect(s.expiresAt, isNull);
    });
  });

  group('DownloadStrategy.fromJson', () {
    test('parses the presigned shape with expiresAt', () {
      final d = DownloadStrategy.fromJson(<String, dynamic>{
        'method': 'presigned',
        'url': 'https://s3-bucket.s3.amazonaws.com/x?X-Amz-Signature=abc',
        'expiresAt': '2025-09-05T01:00:00Z',
      });
      expect(d.method, 'presigned');
      expect(d.url, contains('X-Amz-Signature'));
      expect(d.expiresAt, isNotNull);
      expect(d.headers, isNull);
    });

    test('parses the direct shape', () {
      final d = DownloadStrategy.fromJson(<String, dynamic>{
        'method': 'direct',
        'url': '/api/storage/buckets/avatars/objects/profile.jpg',
      });
      expect(d.method, 'direct');
      expect(d.expiresAt, isNull);
    });
  });

  group('FileOptions', () {
    test('defaults upsert to false', () {
      const o = FileOptions();
      expect(o.contentType, isNull);
      expect(o.upsert, isFalse);
      expect(o.metadata, isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_storage && dart test test/models_test.dart`
Expected: FAIL — model types not defined.

- [ ] **Step 3: Write `models.dart`**

```dart
// packages/insforge_storage/lib/src/models.dart
import 'package:insforge_core/insforge_core.dart';

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
/// the filename extension), whether to [upsert] over an existing object, and
/// optional [metadata].
class FileOptions {
  const FileOptions({
    this.contentType,
    this.upsert = false,
    this.metadata,
  });

  final String? contentType;
  final bool upsert;
  final Map<String, dynamic>? metadata;
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_storage/lib/insforge_storage.dart`:

```dart
export 'src/models.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_storage && dart test test/models_test.dart`
Expected: PASS (all model tests).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_storage/lib/src/models.dart packages/insforge_storage/lib/insforge_storage.dart packages/insforge_storage/test/models_test.dart
git commit -m "feat(storage): add StoredFile/BucketInfo/strategy/FileOptions models"
```

---

## Task 4: Shared test helper — `RecordingAdapter`

**Files:**
- Create: `packages/insforge_storage/test/_recording_adapter.dart`

This is a test-only helper (no library code). It is a custom dio `HttpClientAdapter` that **records each `RequestOptions`** (path, method, query parameters, headers, the decoded JSON body when the request data is JSON, and — critically for storage — whether the request `data is FormData` plus the FormData's field names). It also returns a canned response with controllable status, body (string), and headers. Later tasks assert the exact path + `x-api-key` header presence + that uploads use multipart with a `file` field. There is no behavior to TDD here; the helper is exercised by every subsequent test task.

- [ ] **Step 1: Write the helper**

```dart
// packages/insforge_storage/test/_recording_adapter.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A captured request: the fields storage tests assert against.
class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.headers,
    required this.body,
    required this.isFormData,
    required this.formFieldNames,
    required this.formFileFieldNames,
  });

  final String method;
  final String path;
  final Map<String, dynamic> queryParameters;
  final Map<String, String> headers;

  /// The decoded JSON request body (Map/List), or null when there was none or
  /// the body was multipart.
  final Object? body;

  /// True when the request body was a dio [FormData] (multipart upload).
  final bool isFormData;

  /// Ordered names of the FormData's plain fields (`fields`).
  final List<String> formFieldNames;

  /// Ordered names of the FormData's file parts (`files`).
  final List<String> formFileFieldNames;

  /// All FormData part names in submission order (plain fields then files as
  /// dio serializes them); convenient for asserting the `file` part exists.
  bool get hasFileField => formFileFieldNames.contains('file');
}

/// Records every request and returns a fixed response.
///
/// Configure the canned response with [responseBody] (a JSON-encodable value
/// serialized to a string, or a raw string when [rawBody] is true),
/// [statusCode], and [responseHeaders].
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter({
    Object? responseBody = const <String, dynamic>{},
    this.statusCode = 200,
    this.rawBody = false,
    Map<String, List<String>>? responseHeaders,
  })  : _responseBody = responseBody,
        _responseHeaders = responseHeaders ?? const <String, List<String>>{};

  final Object? _responseBody;
  final int statusCode;
  final bool rawBody;
  final Map<String, List<String>> _responseHeaders;

  final List<CapturedRequest> requests = <CapturedRequest>[];

  /// The single captured request (fails if not exactly one was made).
  CapturedRequest get single => requests.single;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw = options.data;
    final isForm = raw is FormData;

    Object? decodedBody;
    final formFieldNames = <String>[];
    final formFileFieldNames = <String>[];

    if (isForm) {
      for (final MapEntry<String, String> f in raw.fields) {
        formFieldNames.add(f.key);
      }
      for (final MapEntry<String, MultipartFile> f in raw.files) {
        formFileFieldNames.add(f.key);
      }
    } else if (raw is String && raw.isNotEmpty) {
      decodedBody = jsonDecode(raw);
    } else if (raw != null) {
      decodedBody = raw;
    }

    requests.add(
      CapturedRequest(
        method: options.method,
        path: options.path,
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
        headers: options.headers.map(
          (String k, dynamic v) => MapEntry<String, String>(k, '$v'),
        ),
        body: decodedBody,
        isFormData: isForm,
        formFieldNames: formFieldNames,
        formFileFieldNames: formFileFieldNames,
      ),
    );

    final headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      ..._responseHeaders,
    };

    final bodyString = _responseBody == null
        ? ''
        : (rawBody ? _responseBody.toString() : jsonEncode(_responseBody));

    return ResponseBody.fromString(bodyString, statusCode, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: Sanity-check it compiles**

Run: `cd packages/insforge_storage && dart analyze test/_recording_adapter.dart`
Expected: "No issues found!" (it imports only `dart:convert`, `dart:typed_data`, and `dio`, already dependencies).

- [ ] **Step 3: Commit**

```bash
git add packages/insforge_storage/test/_recording_adapter.dart
git commit -m "test(storage): add FormData-aware RecordingAdapter helper"
```

---

## Task 5: `StorageClient` — bucket admin

**Files:**
- Create: `packages/insforge_storage/lib/src/storage_client.dart`
- Test: `packages/insforge_storage/test/bucket_admin_test.dart`
- Modify: `packages/insforge_storage/lib/insforge_storage.dart`

`StorageClient` wraps a shared `InsforgeHttpClient` and exposes bucket-admin methods plus `from(bucket)` (cached per bucket; `StorageFileApi` arrives in Task 6, so this task adds `from` returning it once that type exists — to keep the task self-contained we add a minimal `from` stub that constructs `StorageFileApi`, but `StorageFileApi` is created in Task 6; therefore this task implements ONLY the admin methods and the bucket cache field, and `from` is added in Task 6). Endpoints: `GET/POST /api/storage/buckets`, `PATCH/DELETE /api/storage/buckets/{name}`. Create body is `{bucketName, isPublic}`; update body is `{isPublic}`. List parses the `{buckets: [...]}` array via `BucketInfo.fromJson`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_storage/test/bucket_admin_test.dart
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
    expect(buckets.map((BucketInfo b) => b.name).toList(),
        <String>['avatars', 'documents', 'uploads']);
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_storage && dart test test/bucket_admin_test.dart`
Expected: FAIL — `StorageClient` not defined.

- [ ] **Step 3: Write `storage_client.dart` (admin methods + cache field; `from` added in Task 6)**

```dart
// packages/insforge_storage/lib/src/storage_client.dart
import 'package:insforge_core/insforge_core.dart';

import 'models.dart';

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
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_storage/lib/insforge_storage.dart`:

```dart
export 'src/storage_client.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_storage && dart test test/bucket_admin_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_storage/lib/src/storage_client.dart packages/insforge_storage/lib/insforge_storage.dart packages/insforge_storage/test/bucket_admin_test.dart
git commit -m "feat(storage): add StorageClient bucket administration"
```

---

## Task 6: `StorageFileApi` — direct uploads + `StorageClient.from`

**Files:**
- Create: `packages/insforge_storage/lib/src/storage_file_api.dart`
- Modify: `packages/insforge_storage/lib/src/storage_client.dart` (add `from` + bucket cache)
- Test: `packages/insforge_storage/test/file_upload_test.dart`
- Modify: `packages/insforge_storage/lib/insforge_storage.dart`

`upload` PUTs `multipart/form-data` to `/api/storage/buckets/{bucket}/objects/{path}` with a single file part named `file` (`MultipartFile.fromBytes(bytes, filename: <last path segment>, contentType: MediaType.parse(resolvedContentType))`). The resolved content type is the explicit `contentType`, else inferred via `contentTypeForFilename(path)`. When `upsert` is true it sets the `x-upsert: true` header. `uploadAutoKey` is the same but POSTs to `/api/storage/buckets/{bucket}/objects` (no key in the path), using the filename for content-type inference. Both parse the `StoredFile` response. `x-api-key` is asserted present (inherited from the core client).

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_storage/test/file_upload_test.dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_storage && dart test test/file_upload_test.dart`
Expected: FAIL — `StorageFileApi` / `from` not defined.

- [ ] **Step 3: Write `storage_file_api.dart`**

```dart
// packages/insforge_storage/lib/src/storage_file_api.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:insforge_core/insforge_core.dart';

import 'mime.dart';
import 'models.dart';

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
}
```

- [ ] **Step 4: Add `from` + bucket cache to `StorageClient`**

At the top of `packages/insforge_storage/lib/src/storage_client.dart`, add the import:

```dart
import 'storage_file_api.dart';
```

Inside the `StorageClient` class, add the cache field and `from`:

```dart
  final Map<String, StorageFileApi> _bucketCache = <String, StorageFileApi>{};

  /// Returns the [StorageFileApi] for [bucket], cached per bucket name.
  StorageFileApi from(String bucket) {
    return _bucketCache.putIfAbsent(
      bucket,
      () => StorageFileApi(_http, bucket),
    );
  }
```

- [ ] **Step 5: Export the file API**

Append to `packages/insforge_storage/lib/insforge_storage.dart`:

```dart
export 'src/storage_file_api.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/insforge_storage && dart test test/file_upload_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 7: Commit**

```bash
git add packages/insforge_storage/lib/src/storage_file_api.dart packages/insforge_storage/lib/src/storage_client.dart packages/insforge_storage/lib/insforge_storage.dart packages/insforge_storage/test/file_upload_test.dart
git commit -m "feat(storage): add StorageFileApi direct uploads + from() cache"
```

---

## Task 7: `StorageFileApi` — download, list, delete, getPublicUrl

**Files:**
- Modify: `packages/insforge_storage/lib/src/storage_file_api.dart`
- Test: `packages/insforge_storage/test/file_ops_test.dart`

`download` GETs `/api/storage/buckets/{bucket}/objects/{path}` with `responseType: ResponseType.bytes` and returns `Uint8List.fromList(response.data as List<int>)`. `list` GETs `/objects` with `prefix`/`limit`/`offset`/`search` query params (omitting nulls) and parses the `data` array of `StoredFile`. `delete(String)` DELETEs `/objects/{path}`; `delete(List<String>)` deletes each in turn (the API has no batch delete). `getPublicUrl` constructs `{baseUrl}/api/storage/buckets/{bucket}/objects/{path}` from the core client's `baseUrl`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_storage && dart test test/file_ops_test.dart`
Expected: FAIL — `download`/`list`/`delete`/`deleteAll`/`getPublicUrl` not defined.

- [ ] **Step 3: Add the operations to `storage_file_api.dart`**

Add these methods inside the `StorageFileApi` class (e.g. after the upload methods):

```dart
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
          .map((Map<dynamic, dynamic> e) =>
              StoredFile.fromJson(Map<String, dynamic>.from(e)))
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_storage && dart test test/file_ops_test.dart`
Expected: PASS (all six tests).

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_storage/lib/src/storage_file_api.dart packages/insforge_storage/test/file_ops_test.dart
git commit -m "feat(storage): add download/list/delete/getPublicUrl"
```

---

## Task 8: Strategy flow — `getUploadStrategy`, `getDownloadStrategy`, `confirmUpload`

**Files:**
- Modify: `packages/insforge_storage/lib/src/storage_file_api.dart`
- Test: `packages/insforge_storage/test/strategy_test.dart`

`getUploadStrategy` POSTs `/upload-strategy` with `{filename, contentType?, size?}` (omitting nulls) and parses an `UploadStrategy`. `getDownloadStrategy` GETs `/download-strategy/objects/{path}` (the canonical GET path from `storage.yaml`) and parses a `DownloadStrategy`. (The server auto-calculates expiry from bucket visibility and accepts no body, so `expiresIn` is accepted by the SDK for forward-compat but not sent.) `confirmUpload` POSTs `/objects/{objectKey}/confirm-upload` with `{size, contentType?, etag?}` and parses a `StoredFile`.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_storage && dart test test/strategy_test.dart`
Expected: FAIL — strategy methods not defined.

- [ ] **Step 3: Add the strategy methods to `storage_file_api.dart`**

Add these methods inside the `StorageFileApi` class:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_storage && dart test test/strategy_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_storage/lib/src/storage_file_api.dart packages/insforge_storage/test/strategy_test.dart
git commit -m "feat(storage): add upload/download strategy + confirmUpload"
```

---

## Task 9: `uploadLarge` — presigned S3 path via a separate no-auth Dio

**Files:**
- Modify: `packages/insforge_storage/lib/src/storage_file_api.dart`
- Test: `packages/insforge_storage/test/upload_large_test.dart`

`uploadLarge(path, bytes, {contentType, presignedDio})` first calls `getUploadStrategy(_lastSegment(path), contentType, size)`. When `method == 'presigned'`, it POSTs a multipart body to `strategy.uploadUrl` using the **injected `presignedDio ?? Dio()`** — a plain Dio with NO interceptors and therefore NO `Authorization`/`x-api-key` headers (S3 rejects a Bearer token). The form appends every `strategy.fields` entry FIRST, then the `file` part LAST (required by S3 presigned POST). If `strategy.confirmRequired`, it then calls `confirmUpload(strategy.key, size: ..., contentType: ...)` and returns that `StoredFile`; otherwise it returns a `StoredFile` synthesized from the strategy. When `method == 'direct'`, it falls back to `upload(path, bytes, contentType: ...)`.

The test injects a recording `Dio` (via a recording adapter) so it can assert: (1) the presigned Dio was used for the S3 POST, (2) that request carries NO `Authorization` header, and (3) the `file` field is LAST (all `strategy.fields` keys appear before `file`). It then asserts `confirmUpload` is called on the MAIN client afterward.

- [ ] **Step 1: Write the failing test**

```dart
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
    expect(mainAdapter.requests.map((CapturedRequest r) => r.path).toList(), <String>[
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
```

> Note: `_SequencedAdapter` reuses the shared `RecordingAdapter`'s capture and response logic per call, accumulating each `CapturedRequest` into its own `requests` list while returning the next canned body. This keeps the FormData-introspection logic in one place. `ResponseBody`, `RequestOptions`, and `Uint8List` are already imported by this test file (via `dio` and `dart:typed_data`).

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_storage && dart test test/upload_large_test.dart`
Expected: FAIL — `uploadLarge` not defined.

- [ ] **Step 3: Add `uploadLarge` to `storage_file_api.dart`**

Add this method inside the `StorageFileApi` class:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_storage && dart test test/upload_large_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_storage/lib/src/storage_file_api.dart packages/insforge_storage/test/upload_large_test.dart
git commit -m "feat(storage): add uploadLarge presigned S3 flow (no-auth Dio, file last)"
```

---

## Task 10: Full suite + analyze + CI

**Files:**
- Modify: `.github/workflows/ci.yaml` (add a storage test step)

- [ ] **Step 1: Run the full package suite and analyzer**

Run: `cd packages/insforge_storage && dart test && dart analyze`
Expected: all tests PASS across every test file; "No issues found!"

- [ ] **Step 2: Add a CI step for the package**

In `.github/workflows/ci.yaml` (created in Plan 1), append a test step after the existing per-package steps:

```yaml
      - name: Test insforge_storage
        working-directory: packages/insforge_storage
        run: dart test
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci(storage): run insforge_storage tests"
```

---

## Self-Review Notes

- **Spec coverage (design §4.4):** `StorageClient(http)` with `from(bucket)` (cached, Task 6) and bucket admin `listBuckets`/`createBucket`/`updateBucket`/`deleteBucket` (Task 5). `StorageFileApi` with `upload`/`uploadAutoKey` (Task 6), `download`/`list`/`delete`/`deleteAll`/`getPublicUrl` (Task 7), strategy flow `getUploadStrategy`/`getDownloadStrategy`/`confirmUpload` (Task 8), and the presigned `uploadLarge` with a separate no-auth Dio and file-field-last ordering (Task 9). Models `StoredFile`/`BucketInfo`/`UploadStrategy`/`DownloadStrategy`/`FileOptions` (Task 3) and the extension→MIME helper (Task 2). Endpoints confirmed against `storage.yaml`. Covered.
- **Confirmed wire details (from `storage.yaml`):** `StoredFile` fields = `bucket`/`key`/`size`/`mimeType?`/`uploadedAt`/`url`. List-buckets returns `{buckets: ["a","b"]}` (bare strings) — hence `BucketInfo.fromJson` accepts a string OR an object, defaulting `isPublic` to true. createBucket body = `{bucketName, isPublic}` (POST `/api/storage/buckets`); updateBucket body = `{isPublic}` (PATCH `/api/storage/buckets/{name}`). Upload PUT/POST is `multipart/form-data` with a required `file` part; auto-key POSTs to `/objects`, specific-key PUTs to `/objects/{key}`; `x-upsert` header opts into overwrite. List GET supports `prefix`/`limit`/`offset`/`search` and returns `{data:[StoredFile], pagination}`. `download-strategy` is the canonical **GET** `/download-strategy/objects/{key}` (the old POST `.../objects/{key}/download-strategy` is deprecated; this SDK uses the canonical GET). `upload-strategy` POST body = `{filename, contentType?, size?}`. `confirm-upload` POST body = `{size, contentType?, etag?}`. `UploadStrategy` = `{method, uploadUrl, fields?, key, confirmRequired, confirmUrl?, expiresAt?}`; `DownloadStrategy` = `{method, url, expiresAt?, headers?}`. All routes are secured by the `x-api-key` header.
- **MIME map entries (design-scoped, mirrors Kotlin `CONTENT_TYPE_MAP`):** `jpg`/`jpeg`→`image/jpeg`, `png`→`image/png`, `gif`→`image/gif`, `webp`→`image/webp`, `svg`→`image/svg+xml`, `pdf`→`application/pdf`, `json`→`application/json`, `txt`→`text/plain`, `mp4`→`video/mp4`; default `application/octet-stream`. Lookup is case-insensitive and uses the last path segment.
- **x-api-key requirement:** Storage routes need `x-api-key`, which `InsforgeHttpClient` only emits when constructed with `apiKey`. Every storage test constructs `InsforgeHttpClient(baseUrl:..., anonKey:..., apiKey: 'test-key')` and asserts the header is present; the design note records that the umbrella (Plan 7) supplies the project apiKey.
- **How the separate presigned Dio is tested (Task 9):** `uploadLarge` takes an injectable `presignedDio`. The test passes a plain `Dio()` whose `httpClientAdapter` is a `RecordingAdapter`; because this Dio has no interceptors, the recorded S3 request carries no `Authorization` header — asserted directly. The FormData-aware `RecordingAdapter` records `formFieldNames` (plain fields, in insertion order) separately from `formFileFieldNames` (the `file` part), so the test asserts every `strategy.fields` key precedes the single `file` part — proving "file LAST". The MAIN client uses a `_SequencedAdapter` (a thin subclass of the shared `RecordingAdapter`) that returns the strategy JSON on the first call and the `StoredFile` JSON on the confirm call, letting the test assert the two main-client paths (`upload-strategy` then `confirm-upload`) in order. The direct-strategy test asserts the injected Dio is NOT used and the main client falls back to a multipart PUT.
- **Core API reused (from Plan 1):** `InsforgeHttpClient` (`request`, `.dio`, `.baseUrl`), `parseInsforgeDate` (for `uploadedAt`/`expiresAt`), and the inherited auth-header injection / 401 refresh / error mapping. `FileOptions` is provided as a value type for callers that prefer an options object, though the per-method named parameters (`contentType`/`upsert`/`metadata`) are the primary surface.
- **Type names later plans/sample must import:** `StorageClient`, `StorageFileApi`, `StoredFile`, `BucketInfo`, `UploadStrategy`, `DownloadStrategy`, `FileOptions`, `contentTypeForFilename` — keep these stable for the umbrella (Plan 7) and the sample app.
- **Deferred / not yet covered:** file-path (`File`)-based upload overloads and `metadata`/`x-metadata` header serialization are out of scope for this pure-Dart package (the umbrella's Flutter layer or a future task can add `File` convenience overloads); `metadata` is accepted in the signatures for API stability but not yet serialized to a header.
