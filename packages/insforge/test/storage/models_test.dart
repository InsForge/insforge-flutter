// packages/insforge_storage/test/models_test.dart
import 'package:insforge/insforge.dart';
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
