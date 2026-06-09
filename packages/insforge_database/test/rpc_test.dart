// packages/insforge_database/test/rpc_test.dart
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
  test('rpc with no args uses GET and the rpc path', () async {
    final adapter = RecordingAdapter(
      responseBody: <dynamic>[
        <String, dynamic>{'id': 1},
      ],
    );
    final db = DatabaseClient(_client(adapter));

    final result = await db.rpc('get_all_active_users').execute();

    final req = adapter.single;
    expect(req.method, 'GET');
    expect(req.path, '/api/database/rpc/get_all_active_users');
    expect(req.body, isNull);
    expect((result as List<dynamic>).single, <String, dynamic>{'id': 1});
  });

  test('rpc with args uses POST and sends the args body', () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{'count': 3},
    );
    final db = DatabaseClient(_client(adapter));

    final result = await db
        .rpc('get_user_stats', args: <String, dynamic>{'user_id': 123})
        .execute();

    final req = adapter.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/database/rpc/get_user_stats');
    expect(req.body, <String, dynamic>{'user_id': 123});
    expect((result as Map<String, dynamic>)['count'], 3);
  });

  test('rpc with an empty args map still uses GET', () async {
    final adapter = RecordingAdapter(responseBody: <dynamic>[]);
    final db = DatabaseClient(_client(adapter));

    await db.rpc('noop', args: <String, dynamic>{}).execute();

    expect(adapter.single.method, 'GET');
  });
}
