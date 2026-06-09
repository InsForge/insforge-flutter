// integration_tests/test/database_test.dart
//
// Database module integration tests, exercising the PostgREST-style query
// builder. Needs the fixed pre-verified account (authConfigured).
//
// Prerequisite: a table `sdk_test` on the test project with at least:
//     id      (PRIMARY KEY — InsForge defaults to a uuid/text id, but an
//              integer serial works too; the suite treats id as opaque)
//     name    text NOT NULL
//     value   text
//     score   integer DEFAULT 0
//
// Because `id` may be a uuid string or an integer depending on how the table
// was created, this suite never assumes its Dart type — ids are kept as
// `Object` and passed straight back to filters.
//
// When the table is absent the suite degrades to asserting that the SDK
// surfaces an InsforgeHttpException, rather than failing.
import 'package:insforge_core/insforge_core.dart';
import 'package:insforge_database/insforge_database.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

const String _table = 'sdk_test';

void main() {
  group(
    'Database Module',
    () {
      late DatabaseClient db;
      final List<Object> insertedIds = <Object>[];
      var tableAvailable = true;

      setUpAll(() async {
        final http = await env.signedInHttpClient();
        db = DatabaseClient(http);

        // Probe the table.
        try {
          await db.from(_table).select('id').limit(1).execute();
        } on InsforgeHttpException catch (e) {
          final msg = e.message.toLowerCase();
          final isMissing = e.statusCode == 404 ||
              (e.error ?? '').contains('42P01') ||
              msg.contains('relation') ||
              msg.contains('does not exist') ||
              msg.contains('not found');
          if (isMissing) {
            tableAvailable = false;
            printOnFailure(
              'Table "$_table" not found – database tests verify error '
              'handling only.',
            );
          } else {
            rethrow;
          }
        }
      });

      tearDownAll(() async {
        if (tableAvailable && insertedIds.isNotEmpty) {
          try {
            await db
                .from(_table)
                .inFilter('id', insertedIds)
                .delete()
                .execute();
          } catch (_) {
            // Best-effort cleanup.
          }
        }
      });

      test('degrades cleanly when the table is missing', () async {
        if (tableAvailable) {
          // Table present – this assertion does not apply.
          return;
        }
        await expectLater(
          db.from(_table).select().limit(1).execute(),
          throwsA(isA<InsforgeHttpException>()),
        );
      });

      test('select returns a list of rows', () async {
        if (!tableAvailable) return;
        final rows = await db.from(_table).select().limit(5).execute();
        expect(rows, isA<List<Map<String, dynamic>>>());
      });

      test('select specific columns', () async {
        if (!tableAvailable) return;
        final rows = await db.from(_table).select('id,name').limit(3).execute();
        expect(rows, isA<List<Map<String, dynamic>>>());
        if (rows.isNotEmpty) {
          expect(rows.first.containsKey('id'), isTrue);
          expect(rows.first.containsKey('name'), isTrue);
        }
      });

      test('count returns a number', () async {
        if (!tableAvailable) return;
        final total = await db.from(_table).count();
        expect(total, isA<int>());
        expect(total, greaterThanOrEqualTo(0));
      });

      test('impossible filter yields an empty list', () async {
        if (!tableAvailable) return;
        final rows = await db
            .from(_table)
            .select()
            .eq('name', 'nonexistent-${DateTime.now().microsecondsSinceEpoch}')
            .execute();
        expect(rows, isEmpty);
      });

      test('insert single row (returns it via .select())', () async {
        if (!tableAvailable) return;
        final name = 'insert-single-${DateTime.now().microsecondsSinceEpoch}';
        final rows = await db
            .from(_table)
            .insert(<String, dynamic>{
              'name': name,
              'value': 'single',
              'score': 10,
            })
            .select()
            .execute();

        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row['name'], name);
        expect(row['value'], 'single');
        expect(row['score'], 10);
        insertedIds.add(row['id'] as Object);
      });

      test('insert multiple rows (batch)', () async {
        if (!tableAvailable) return;
        final ts = DateTime.now().microsecondsSinceEpoch;
        final rows = await db
            .from(_table)
            .insert(<Map<String, dynamic>>[
              <String, dynamic>{'name': 'batch-a-$ts', 'value': 'batch', 'score': 20},
              <String, dynamic>{'name': 'batch-b-$ts', 'value': 'batch', 'score': 30},
            ])
            .select()
            .execute();

        expect(rows, hasLength(2));
        for (final row in rows) {
          insertedIds.add(row['id'] as Object);
        }
      });

      test('update a row', () async {
        if (!tableAvailable) return;
        final tag = 'update-${DateTime.now().microsecondsSinceEpoch}';
        final inserted = await db
            .from(_table)
            .insert(<String, dynamic>{'name': tag, 'value': 'before', 'score': 0})
            .select()
            .execute();
        final Object id = inserted.first['id'] as Object;
        insertedIds.add(id);

        final updated = await db
            .from(_table)
            .eq('id', id)
            .update(<String, dynamic>{'value': 'after', 'score': 99})
            .select()
            .execute();

        expect(updated, hasLength(1));
        expect(updated.first['value'], 'after');
        expect(updated.first['score'], 99);
      });

      test('upsert inserts when row is new', () async {
        if (!tableAvailable) return;
        final tag = 'upsert-${DateTime.now().microsecondsSinceEpoch}';
        final rows = await db
            .from(_table)
            .upsert(<String, dynamic>{
              'name': tag,
              'value': 'upserted',
              'score': 50,
            })
            .select()
            .execute();

        expect(rows, hasLength(1));
        expect(rows.first['name'], tag);
        insertedIds.add(rows.first['id'] as Object);
      });

      test('delete removes matching rows', () async {
        if (!tableAvailable) return;
        final tag = 'delete-${DateTime.now().microsecondsSinceEpoch}';
        final inserted = await db
            .from(_table)
            .insert(<String, dynamic>{'name': tag, 'value': 'to-delete'})
            .select()
            .execute();
        final Object id = inserted.first['id'] as Object;

        await db.from(_table).eq('id', id).delete().execute();

        final check =
            await db.from(_table).select('id').eq('id', id).execute();
        expect(check, isEmpty);
      });

      group('filters', () {
        late List<Object> seedIds;
        late String tag;

        setUp(() async {
          if (!tableAvailable) return;
          tag = 'filter-${DateTime.now().microsecondsSinceEpoch}';
          final seeded = await db
              .from(_table)
              .insert(<Map<String, dynamic>>[
                <String, dynamic>{'name': '$tag-alpha', 'value': 'hello world', 'score': 10},
                <String, dynamic>{'name': '$tag-beta', 'value': 'hello earth', 'score': 20},
                <String, dynamic>{'name': '$tag-gamma', 'value': 'goodbye world', 'score': 30},
              ])
              .select()
              .execute();
          seedIds =
              seeded.map((Map<String, dynamic> r) => r['id'] as Object).toList();
          insertedIds.addAll(seedIds);
        });

        test('eq matches exact value', () async {
          if (!tableAvailable) return;
          final rows =
              await db.from(_table).select().eq('name', '$tag-alpha').execute();
          expect(rows, hasLength(1));
          expect(rows.first['name'], '$tag-alpha');
        });

        test('neq excludes a value', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select('name')
              .neq('name', '$tag-alpha')
              .like('name', '$tag-%')
              .execute();
          expect(
            rows.every((Map<String, dynamic> r) => r['name'] != '$tag-alpha'),
            isTrue,
          );
        });

        test('gt / lt compare numerically', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select('name,score')
              .gt('score', 15)
              .lt('score', 25)
              .like('name', '$tag-%')
              .execute();
          expect(rows, hasLength(1));
          expect(rows.first['score'], 20);
        });

        test('gte / lte are inclusive', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select('name,score')
              .gte('score', 20)
              .lte('score', 30)
              .like('name', '$tag-%')
              .execute();
          expect(rows.length, greaterThanOrEqualTo(2));
        });

        test('like matches a pattern', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select('value')
              .like('value', '%world%')
              .like('name', '$tag-%')
              .execute();
          expect(rows.length, greaterThanOrEqualTo(1));
          for (final r in rows) {
            expect((r['value'] as String).contains('world'), isTrue);
          }
        });

        test('ilike matches case-insensitively', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select('value')
              .ilike('value', '%HELLO%')
              .like('name', '$tag-%')
              .execute();
          expect(rows.length, greaterThanOrEqualTo(1));
        });

        test('inFilter matches multiple values', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select('name')
              .inFilter('name', <Object>['$tag-alpha', '$tag-gamma'])
              .execute();
          expect(rows.length, greaterThanOrEqualTo(2));
        });

        test('order sorts results', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select('score')
              .like('name', '$tag-%')
              .order('score')
              .execute();
          if (rows.length >= 2) {
            expect(
              (rows[0]['score'] as int) <= (rows[1]['score'] as int),
              isTrue,
            );
          }
        });

        test('limit caps the result count', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select()
              .like('name', '$tag-%')
              .limit(1)
              .execute();
          expect(rows.length, lessThanOrEqualTo(1));
        });

        test('range paginates results', () async {
          if (!tableAvailable) return;
          final rows = await db
              .from(_table)
              .select()
              .like('name', '$tag-%')
              .range(0, 1)
              .execute();
          expect(rows.length, lessThanOrEqualTo(2));
        });

        test('single returns one row', () async {
          if (!tableAvailable) return;
          final row =
              await db.from(_table).select().eq('id', seedIds.first).single();
          expect(row['id'], seedIds.first);
        });
      });
    },
    skip: env.authSkipReason,
  );
}
