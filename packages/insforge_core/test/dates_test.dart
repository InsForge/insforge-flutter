// packages/insforge_core/test/dates_test.dart
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseInsforgeDate', () {
    test('parses ISO8601 with fractional seconds and Z', () {
      final d = parseInsforgeDate('2026-06-08T10:30:00.123Z');
      expect(d, isNotNull);
      expect(d!.isUtc, isTrue);
      expect(d.year, 2026);
      expect(d.millisecond, 123);
    });

    test('parses a date-only value', () {
      final d = parseInsforgeDate('2026-06-08');
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 6);
      expect(d.day, 8);
    });

    test('returns null for null or empty', () {
      expect(parseInsforgeDate(null), isNull);
      expect(parseInsforgeDate(''), isNull);
    });

    test('returns null for an unparseable value', () {
      expect(parseInsforgeDate('not-a-date'), isNull);
    });
  });
}
