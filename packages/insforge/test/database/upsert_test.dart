// packages/insforge_database/test/upsert_test.dart
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
  test('upsert sends an array body and resolution=merge-duplicates', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('users').upsert(
      <String, dynamic>{'email': 'a@x.com', 'name': 'A'},
    ).execute();

    final req = adapter.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/database/records/users');
    expect(req.body, <dynamic>[
      <String, dynamic>{'email': 'a@x.com', 'name': 'A'},
    ]);
    expect(req.headers['Prefer'], 'resolution=merge-duplicates');
  });

  test('onConflict adds the on_conflict query param', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.from('users').upsert(
      <String, dynamic>{'email': 'a@x.com'},
      onConflict: 'email',
    ).execute();

    expect(adapter.single.queryParameters['on_conflict'], 'email');
  });

  test('ignoreDuplicates switches resolution and .select() appends return',
      () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db
        .from('users')
        .upsert(
          <Map<String, dynamic>>[
            <String, dynamic>{'email': 'a@x.com'},
          ],
          ignoreDuplicates: true,
        )
        .select()
        .execute();

    expect(
      adapter.single.headers['Prefer'],
      'resolution=ignore-duplicates,return=representation',
    );
  });
}
