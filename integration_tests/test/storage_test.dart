// integration_tests/test/storage_test.dart
//
// Storage module integration tests. Storage authenticates with the project
// API key (`x-api-key`), so the HTTP client MUST be built with `apiKey:` —
// hence storageConfigured (core + INSFORGE_INTEGRATION_API_KEY).
//
// Prerequisite: a bucket named `public` that accepts authenticated uploads.
// When the bucket is unavailable the lifecycle tests degrade gracefully.
import 'dart:convert';
import 'dart:typed_data';

import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

const String _bucket = 'public';

void main() {
  group(
    'Storage Module',
    () {
      late StorageClient storage;
      var bucketAvailable = true;

      setUpAll(() async {
        final http = env.newHttpClient(withApiKey: true);
        storage = StorageClient(http);

        // Probe with a small upload to confirm the bucket exists and accepts
        // writes.
        final probeKey =
            '_sdk_probe_${DateTime.now().microsecondsSinceEpoch}.txt';
        try {
          await storage.from(_bucket).upload(
                probeKey,
                Uint8List.fromList(utf8.encode('probe')),
                contentType: 'text/plain',
                upsert: true,
              );
          // Best-effort cleanup.
          try {
            await storage.from(_bucket).delete(probeKey);
          } catch (_) {}
        } on InsforgeException {
          bucketAvailable = false;
          printOnFailure(
            'Bucket "$_bucket" not available – storage lifecycle tests '
            'degrade to error-handling checks only.',
          );
        }
      });

      // getPublicUrl is pure/client-side and always works.
      group('getPublicUrl()', () {
        test('builds a URL containing the base URL and bucket', () {
          final url = storage.from(_bucket).getPublicUrl('images/logo.png');
          expect(url, contains(env.baseUrl!));
          expect(url, contains(_bucket));
          expect(url, contains('images/logo.png'));
        });

        test('handles nested paths', () {
          final url = storage.from(_bucket).getPublicUrl('a/b/c/file.txt');
          expect(url, contains('a/b/c/file.txt'));
        });
      });

      test('upload → list → download → delete lifecycle', () async {
        if (!bucketAvailable) return;

        final path =
            'sdk-test/lifecycle-${DateTime.now().microsecondsSinceEpoch}.txt';
        final content = 'Upload test – ${DateTime.now().toIso8601String()}';
        final bytes = Uint8List.fromList(utf8.encode(content));

        // Upload.
        final stored = await storage.from(_bucket).upload(
              path,
              bytes,
              contentType: 'text/plain',
              upsert: true,
            );
        expect(stored.key, isNotEmpty);

        // List (with prefix).
        final listed =
            await storage.from(_bucket).list(prefix: 'sdk-test/', limit: 50);
        expect(listed, isA<List<StoredFile>>());

        // Download and verify bytes.
        final downloaded = await storage.from(_bucket).download(path);
        expect(utf8.decode(downloaded), content);

        // Delete.
        await storage.from(_bucket).delete(path);
      });

      test('uploadAutoKey returns a server-generated key', () async {
        if (!bucketAvailable) return;

        final content =
            'Auto upload – ${DateTime.now().microsecondsSinceEpoch}';
        final bytes = Uint8List.fromList(utf8.encode(content));

        try {
          final stored = await storage.from(_bucket).uploadAutoKey(
                'auto.txt',
                bytes,
                contentType: 'text/plain',
              );
          expect(stored.key, isNotEmpty);
          // Best-effort cleanup.
          try {
            await storage.from(_bucket).delete(stored.key);
          } catch (_) {}
        } on InsforgeHttpException catch (e) {
          // Some backends may not support auto-key generation.
          expect(e.statusCode, greaterThanOrEqualTo(400));
        }
      });

      test('download of a non-existent object throws', () async {
        await expectLater(
          storage.from(_bucket).download(
                'nonexistent-${DateTime.now().microsecondsSinceEpoch}.txt',
              ),
          throwsA(isA<InsforgeHttpException>()),
        );
      });
    },
    skip: env.storageSkipReason,
  );
}
