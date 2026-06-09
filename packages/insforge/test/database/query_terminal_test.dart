// packages/insforge_database/test/query_terminal_test.dart
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

class _Post {
  _Post(this.id, this.title);
  final int id;
  final String title;
  factory _Post.fromJson(Map<String, dynamic> json) =>
      _Post(json['id'] as int, json['title'] as String);
}

void main() {
  test('single sets the pgrst.object Accept header and returns one map',
      () async {
    final adapter = RecordingAdapter(
      responseBody: <String, dynamic>{'id': 7, 'title': 'only'},
    );
    final db = DatabaseClient(_client(adapter));

    final row = await db.from('posts').eq('id', 7).single();

    expect(row['title'], 'only');
    expect(
      adapter.single.headers['Accept'],
      'application/vnd.pgrst.object+json',
    );
    expect(adapter.single.queryParameters['id'], 'eq.7');
  });

  test('executeAs maps each row via fromJson', () async {
    final adapter = RecordingAdapter(
      responseBody: <dynamic>[
        <String, dynamic>{'id': 1, 'title': 'a'},
        <String, dynamic>{'id': 2, 'title': 'b'},
      ],
    );
    final db = DatabaseClient(_client(adapter));

    final posts = await db.from('posts').executeAs(_Post.fromJson);

    expect(posts, hasLength(2));
    expect(posts[1].title, 'b');
  });

  test('count sends Prefer count and reads X-Total-Count', () async {
    final adapter = RecordingAdapter(
      responseBody: <dynamic>[],
      responseHeaders: <String, List<String>>{
        'X-Total-Count': <String>['42'],
      },
    );
    final db = DatabaseClient(_client(adapter));

    final total = await db.from('posts').eq('status', 'active').count();

    expect(total, 42);
    expect(adapter.single.headers['Prefer'], 'count=exact');
    expect(adapter.single.queryParameters['status'], 'eq.active');
    expect(adapter.single.queryParameters['limit'], '0');
  });

  test('count falls back to the Content-Range total', () async {
    final adapter = RecordingAdapter(
      responseBody: <dynamic>[],
      responseHeaders: <String, List<String>>{
        'Content-Range': <String>['0-0/123'],
      },
    );
    final db = DatabaseClient(_client(adapter));

    final total = await db.from('posts').count(type: CountType.estimated);

    expect(total, 123);
    expect(adapter.single.headers['Prefer'], 'count=estimated');
  });
}
