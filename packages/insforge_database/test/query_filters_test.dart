// packages/insforge_database/test/query_filters_test.dart
import 'package:insforge_core/insforge_core.dart';
import 'package:insforge_database/insforge_database.dart';
import 'package:test/test.dart';

import '_recording_adapter.dart';

InsforgeHttpClient _client(RecordingAdapter adapter) {
  final client = InsforgeHttpClient(
    baseUrl: 'https://x.insforge.app',
    anonKey: 'anon',
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  test('chained filters + shaping build the expected path and query params',
      () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db
        .from('posts')
        .select('id,title')
        .eq('status', 'active')
        .order('createdAt', ascending: false)
        .limit(10)
        .offset(5)
        .execute();

    final req = adapter.single;
    expect(req.method, 'GET');
    expect(req.path, '/api/database/records/posts');
    expect(req.queryParameters, <String, dynamic>{
      'select': 'id,title',
      'status': 'eq.active',
      'order': 'createdAt.desc',
      'limit': '10',
      'offset': '5',
    });
  });

  test('each comparison operator maps to op.value', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db
        .from('users')
        .neq('role', 'admin')
        .gt('age', 18)
        .gte('score', 5)
        .lt('age', 65)
        .lte('score', 100)
        .like('name', 'A%')
        .ilike('email', '%@x.com')
        .execute();

    expect(adapter.single.queryParameters, <String, dynamic>{
      'role': 'neq.admin',
      // Two filters on the same column accumulate (PostgREST ANDs them);
      // dio serializes the list as repeated params (age=gt.18&age=lt.65).
      'age': <String>['gt.18', 'lt.65'],
      'score': <String>['gte.5', 'lte.100'],
      'name': 'like.A%',
      'email': 'ilike.%@x.com',
    });
  });

  test('a single filter on a column stays a bare string (not a list)', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('t').eq('status', 'active').execute();
    expect(adapter.single.queryParameters['status'], 'eq.active');
  });

  test('isFilter encodes null and booleans', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('t').isFilter('deleted_at', null).execute();
    expect(adapter.single.queryParameters['deleted_at'], 'is.null');

    final adapter2 = RecordingAdapter(responseBody: <dynamic>[]);
    final db2 = DatabaseClient(_client(adapter2));
    await db2.from('t').isFilter('active', true).execute();
    expect(adapter2.single.queryParameters['active'], 'is.true');
  });

  test('inFilter builds an in.(a,b,c) list', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('t').inFilter('id', <Object>[1, 2, 3]).execute();
    expect(adapter.single.queryParameters['id'], 'in.(1,2,3)');
  });

  test('contains/containedBy/or/not/filter/textSearch escape hatches', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db
        .from('t')
        .contains('tags', '{a,b}')
        .containedBy('roles', '{x,y}')
        .or('age.lt.18,age.gt.65')
        .not('status', 'eq', 'archived')
        .filter('id', 'in', '(1,2)')
        .textSearch('body', 'hello', type: TextSearchType.websearch)
        .execute();

    final q = adapter.single.queryParameters;
    expect(q['tags'], 'cs.{a,b}');
    expect(q['roles'], 'cd.{x,y}');
    expect(q['or'], '(age.lt.18,age.gt.65)');
    expect(q['status'], 'not.eq.archived');
    expect(q['id'], 'in.(1,2)');
    expect(q['body'], 'wfts.hello');
  });

  test('textSearch with a config wraps the config in parens', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db
        .from('t')
        .textSearch(
          'body',
          'fat & cat',
          type: TextSearchType.full,
          config: 'english',
        )
        .execute();

    expect(adapter.single.queryParameters['body'], 'fts(english).fat & cat');
  });

  test('range sets offset=from and limit=to-from+1', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('t').range(0, 9).execute();
    expect(adapter.single.queryParameters['offset'], '0');
    expect(adapter.single.queryParameters['limit'], '10');
  });

  test('execute returns the decoded list of maps', () async {
    final adapter = RecordingAdapter(
      responseBody: <dynamic>[
        <String, dynamic>{'id': 1, 'title': 'a'},
        <String, dynamic>{'id': 2, 'title': 'b'},
      ],
    );
    final db = DatabaseClient(_client(adapter));

    final rows = await db.from('posts').execute();
    expect(rows, hasLength(2));
    expect(rows.first['title'], 'a');
  });
}
