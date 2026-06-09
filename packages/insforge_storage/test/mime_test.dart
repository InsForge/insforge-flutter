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
      expect(
        contentTypeForFilename('archive.unknownext'),
        'application/octet-stream',
      );
      expect(contentTypeForFilename('noextension'), 'application/octet-stream');
      expect(contentTypeForFilename(''), 'application/octet-stream');
    });
  });
}
