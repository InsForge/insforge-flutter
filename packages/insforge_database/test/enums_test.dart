// packages/insforge_database/test/enums_test.dart
import 'package:insforge_database/insforge_database.dart';
import 'package:test/test.dart';

void main() {
  test('TextSearchType wire values match PostgREST', () {
    expect(TextSearchType.plain.value, 'plfts');
    expect(TextSearchType.phrase.value, 'phfts');
    expect(TextSearchType.websearch.value, 'wfts');
    expect(TextSearchType.full.value, 'fts');
  });

  test('CountType prefer tokens are lowercase names', () {
    expect(CountType.exact.preferToken, 'exact');
    expect(CountType.planned.preferToken, 'planned');
    expect(CountType.estimated.preferToken, 'estimated');
  });
}
