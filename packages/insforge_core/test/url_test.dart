// packages/insforge_core/test/url_test.dart
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('adds https scheme when missing and trims trailing slash', () {
      expect(normalizeBaseUrl('api.example.com/'), 'https://api.example.com');
    });

    test('keeps an explicit http scheme', () {
      expect(normalizeBaseUrl('http://localhost:7130'), 'http://localhost:7130');
    });

    test('uses http when useHttps is false and no scheme given', () {
      expect(
        normalizeBaseUrl('localhost:7130', useHttps: false),
        'http://localhost:7130',
      );
    });

    test('rejects URLs that already contain a module path', () {
      expect(
        () => normalizeBaseUrl('https://x.com/api/auth'),
        throwsA(isA<InsforgeException>()),
      );
    });

    test('rejects an empty URL', () {
      expect(() => normalizeBaseUrl('   '), throwsA(isA<InsforgeException>()));
    });
  });
}
