// packages/insforge_database/test/mutation_test.dart
import 'package:insforge/insforge.dart';
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
  test('insert of a single map sends a one-element JSON array, no Prefer',
      () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('posts').insert(<String, dynamic>{'title': 'hi'}).execute();

    final req = adapter.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/database/records/posts');
    expect(req.body, <dynamic>[
      <String, dynamic>{'title': 'hi'},
    ]);
    expect(req.headers.containsKey('Prefer'), isFalse);
  });

  test('insert of a list passes the array through unchanged', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('posts').insert(<Map<String, dynamic>>[
      <String, dynamic>{'title': 'a'},
      <String, dynamic>{'title': 'b'},
    ]).execute();

    expect(adapter.single.body, <dynamic>[
      <String, dynamic>{'title': 'a'},
      <String, dynamic>{'title': 'b'},
    ]);
  });

  test('.select() sets Prefer return=representation and returns rows',
      () async {
    final adapter = RecordingAdapter(
      responseBody: <dynamic>[
        <String, dynamic>{'id': 1, 'title': 'hi'},
      ],
    );
    final db = DatabaseClient(_client(adapter));

    final rows = await db
        .from('posts')
        .insert(<String, dynamic>{'title': 'hi'})
        .select()
        .execute();

    expect(adapter.single.headers['Prefer'], 'return=representation');
    expect(rows.single['id'], 1);
  });

  test('update carries filters as query params and sends the body object',
      () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db
        .from('posts')
        .eq('id', 5)
        .update(<String, dynamic>{'title': 'edited'}).execute();

    final req = adapter.single;
    expect(req.method, 'PATCH');
    expect(req.queryParameters['id'], 'eq.5');
    expect(req.body, <String, dynamic>{'title': 'edited'});
  });

  test('delete carries filters and uses DELETE', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('posts').eq('id', 5).delete().execute();

    final req = adapter.single;
    expect(req.method, 'DELETE');
    expect(req.queryParameters['id'], 'eq.5');
  });
}
