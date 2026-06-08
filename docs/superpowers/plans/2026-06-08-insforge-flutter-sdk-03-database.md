# InsForge Flutter SDK — Plan 3: `insforge_database` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart `insforge_database` package: a PostgREST-style record CRUD layer with a fluent query builder over the InsForge records API. It exposes `DatabaseClient(http)` with `from(table)` and `rpc(fn)`; a `QueryBuilder` accumulating PostgREST query params (filters, ordering, pagination); terminals `execute`, `executeAs`, `single`, `count`; and mutation builders for `insert`, `update`, `delete`, `upsert` that opt into returned representation via `.select()`.

**Architecture:** `insforge_database` depends only on `insforge_core` (built in Plan 1) and reuses its `InsforgeHttpClient`, exception hierarchy, and options. The query builder is **mutable and returns `this`** (mirroring the Kotlin SDK's `TableQuery`) so chained calls accumulate state in a single object; this keeps the implementation simple and the URL-construction logic in one place. Each filter operator appends a PostgREST `column=op.value` query parameter. Mutations build a separate body and (optionally) a `Prefer` header. All requests go through the shared `InsforgeHttpClient.request`, so auth-header injection, single-flight 401 refresh, and error mapping are inherited for free. No Flutter dependency.

**Tech Stack:** Dart ≥ 3.5 (pub workspaces), `dio` ^5.7.0, `meta` ^1.15.0, `insforge_core` (path dependency); dev: `test`, `lints`, `http_mock_adapter` ^0.6.1.

**Prerequisite:** The Flutter SDK (which bundles Dart) must be installed and on `PATH` (`dart --version` must work). It is not currently installed on this machine — install it before executing. Plan 1 (`insforge_core`) must be complete and on disk at `packages/insforge_core`.

**Plan series:** This is plan 3 of 7. Earlier: 01 core, 02 auth. Subsequent: 04 storage, 05 functions, 06 ai, 07 umbrella + sample. This plan appends `packages/insforge_database` to the workspace member list created in Plan 1.

---

## File Structure

```
insforge-flutter/
├── pubspec.yaml                              # MODIFIED: append packages/insforge_database to workspace
└── packages/
    └── insforge_database/
        ├── pubspec.yaml
        ├── analysis_options.yaml             # includes root lints
        ├── lib/
        │   ├── insforge_database.dart        # public exports
        │   └── src/
        │       ├── enums.dart                # CountType, TextSearchType
        │       ├── query_builder.dart        # QueryBuilder (filters + shaping + terminals)
        │       ├── mutation_builder.dart      # InsertBuilder/UpdateBuilder/DeleteBuilder/UpsertBuilder
        │       ├── rpc_builder.dart           # RpcBuilder
        │       └── database_client.dart       # DatabaseClient
        └── test/
            ├── _recording_adapter.dart        # shared RecordingAdapter test helper
            ├── query_filters_test.dart        # eq/neq/gt/in/is/like/order/limit/offset/range/select → params
            ├── query_terminal_test.dart       # execute / executeAs / single / count
            ├── mutation_test.dart             # insert/update/delete + .select() Prefer header
            ├── upsert_test.dart               # resolution Prefer + on_conflict
            └── rpc_test.dart                  # GET vs POST routing
```

---

## Task 1: Package scaffolding

**Files:**
- Create: `packages/insforge_database/pubspec.yaml`
- Create: `packages/insforge_database/analysis_options.yaml`
- Create: `packages/insforge_database/lib/insforge_database.dart`
- Modify: `pubspec.yaml` (workspace root)

- [ ] **Step 1: Create the package `pubspec.yaml`**

```yaml
# packages/insforge_database/pubspec.yaml
name: insforge_database
description: PostgREST-style record CRUD and a fluent query builder for the InsForge Flutter SDK.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.5.0

dependencies:
  dio: ^5.7.0
  meta: ^1.15.0
  insforge_core:
    path: ../insforge_core

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  http_mock_adapter: ^0.6.1
```

- [ ] **Step 2: Create the package-local `analysis_options.yaml`**

```yaml
# packages/insforge_database/analysis_options.yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 3: Create a placeholder library export file**

```dart
// packages/insforge_database/lib/insforge_database.dart
/// PostgREST-style database access for the InsForge Flutter SDK.
library insforge_database;

// Exports are added as each component lands in later tasks.
```

- [ ] **Step 4: Add the package to the workspace**

In the root `pubspec.yaml`, append the new package path to the `workspace:` list so it reads:

```yaml
# pubspec.yaml (root) — workspace section
workspace:
  - packages/insforge_core
  - packages/insforge_auth
  - packages/insforge_database
```

(If Plan 2's `packages/insforge_auth` line is not yet present, just ensure `packages/insforge_database` is listed alongside `packages/insforge_core`.)

- [ ] **Step 5: Resolve dependencies**

Run: `dart pub get` (from repo root)
Expected: resolves the workspace including `insforge_database`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/insforge_database/pubspec.yaml packages/insforge_database/analysis_options.yaml packages/insforge_database/lib/insforge_database.dart
git commit -m "feat(database): add insforge_database package skeleton"
```

---

## Task 2: Enums (`CountType`, `TextSearchType`)

**Files:**
- Create: `packages/insforge_database/lib/src/enums.dart`
- Test: `packages/insforge_database/test/enums_test.dart`
- Modify: `packages/insforge_database/lib/insforge_database.dart`

The `TextSearchType` wire values are confirmed from `records.yaml`/PostgREST and the Kotlin/Swift SDKs: `fts` (to_tsquery), `plfts` (plainto_tsquery, default), `phfts` (phraseto_tsquery), `wfts` (websearch_to_tsquery). `CountType` maps to the `Prefer: count=exact|planned|estimated` token.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_database && dart test test/enums_test.dart`
Expected: FAIL — `TextSearchType`/`CountType` not defined.

- [ ] **Step 3: Write `enums.dart`**

```dart
// packages/insforge_database/lib/src/enums.dart

/// Count algorithm for `count()` queries, sent as `Prefer: count=<token>`.
enum CountType {
  /// Exact count (full scan). Most accurate, slowest.
  exact,

  /// Planner estimate. Fast, may be inaccurate after bulk writes.
  planned,

  /// Statistics-based estimate. Fastest, least accurate.
  estimated;

  /// The `Prefer: count=` token for this algorithm.
  String get preferToken => name;
}

/// Full-text search parsing strategy, mapped to its PostgREST operator.
///
/// * [plain] → `plfts` (plainto_tsquery) — default.
/// * [phrase] → `phfts` (phraseto_tsquery).
/// * [websearch] → `wfts` (websearch_to_tsquery).
/// * [full] → `fts` (to_tsquery, raw tsquery syntax).
enum TextSearchType {
  plain('plfts'),
  phrase('phfts'),
  websearch('wfts'),
  full('fts');

  const TextSearchType(this.value);

  /// The PostgREST operator string for this search type.
  final String value;
}
```

- [ ] **Step 4: Export it**

In `packages/insforge_database/lib/insforge_database.dart`, replace the trailing comment with:

```dart
export 'src/enums.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_database && dart test test/enums_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_database/lib/src/enums.dart packages/insforge_database/lib/insforge_database.dart packages/insforge_database/test/enums_test.dart
git commit -m "feat(database): add CountType and TextSearchType enums"
```

---

## Task 3: Shared test helper — `RecordingAdapter`

**Files:**
- Create: `packages/insforge_database/test/_recording_adapter.dart`

This is a test-only helper (no library code). It is a custom dio `HttpClientAdapter` that **records each `RequestOptions`** (path, query parameters, method, headers, and decoded request body) and returns a canned response with controllable status, body, and headers. Later tasks assert the exact URL path + query params + headers the builder produces. There is no behavior to TDD here; the helper is exercised by every subsequent test task.

- [ ] **Step 1: Write the helper**

```dart
// packages/insforge_database/test/_recording_adapter.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A captured request: the fields tests assert against.
class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, dynamic> queryParameters;
  final Map<String, String> headers;

  /// The decoded JSON request body (List/Map), or null when there was none.
  final Object? body;
}

/// Records every request and returns a fixed response.
///
/// Configure the canned response with [responseBody] (a JSON-encodable
/// value), [statusCode], and [responseHeaders] (e.g. Content-Range).
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter({
    Object? responseBody = const <dynamic>[],
    this.statusCode = 200,
    Map<String, List<String>>? responseHeaders,
  })  : _responseBody = responseBody,
        _responseHeaders = responseHeaders ?? const <String, List<String>>{};

  final Object? _responseBody;
  final int statusCode;
  final Map<String, List<String>> _responseHeaders;

  final List<CapturedRequest> requests = <CapturedRequest>[];

  /// The single captured request (fails if not exactly one was made).
  CapturedRequest get single => requests.single;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? decodedBody;
    final raw = options.data;
    if (raw is String && raw.isNotEmpty) {
      decodedBody = jsonDecode(raw);
    } else if (raw != null) {
      decodedBody = raw;
    }

    requests.add(
      CapturedRequest(
        method: options.method,
        path: options.path,
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
        headers: options.headers.map(
          (String k, dynamic v) => MapEntry<String, String>(k, '$v'),
        ),
        body: decodedBody,
      ),
    );

    final headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      ..._responseHeaders,
    };

    return ResponseBody.fromString(
      _responseBody == null ? '' : jsonEncode(_responseBody),
      statusCode,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}
```

- [ ] **Step 2: Sanity-check it compiles**

Run: `cd packages/insforge_database && dart analyze test/_recording_adapter.dart`
Expected: "No issues found!" (it imports only `dio`, already a dependency).

- [ ] **Step 3: Commit**

```bash
git add packages/insforge_database/test/_recording_adapter.dart
git commit -m "test(database): add RecordingAdapter request-capture helper"
```

---

## Task 4: `QueryBuilder` — filters + shaping + the read terminal

**Files:**
- Create: `packages/insforge_database/lib/src/query_builder.dart`
- Test: `packages/insforge_database/test/query_filters_test.dart`
- Modify: `packages/insforge_database/lib/insforge_database.dart`

This task builds the read side of `QueryBuilder`: every filter operator, the shaping methods, and `execute()`. Mutations, `single`, `executeAs`, and `count` arrive in later tasks (the class is extended in place). The test drives a `DatabaseClient` constructed in this task too, since `from(table)` is the only public entry point.

- [ ] **Step 1: Write the failing test**

```dart
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
      'age': 'lt.65',
      'score': 'lte.100',
      'name': 'like.A%',
      'email': 'ilike.%@x.com',
    });
    // Note: gt('age') then lt('age') — last write wins for a repeated column.
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
        .textSearch('body', 'fat & cat',
            type: TextSearchType.full, config: 'english')
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_database && dart test test/query_filters_test.dart`
Expected: FAIL — `DatabaseClient`/`QueryBuilder` not defined.

- [ ] **Step 3: Write `query_builder.dart`**

```dart
// packages/insforge_database/lib/src/query_builder.dart
import 'package:insforge_core/insforge_core.dart';

import 'enums.dart';

/// Fluent, mutable builder for PostgREST-style record queries.
///
/// Methods accumulate query parameters and return `this`, so calls chain on a
/// single instance (mirrors the Kotlin SDK's `TableQuery`). Obtain one via
/// [DatabaseClient.from]. Terminal methods (`execute`, `executeAs`, `single`,
/// `count`) perform the request; mutation methods (`insert`, `update`,
/// `delete`, `upsert`) return dedicated mutation builders.
class QueryBuilder {
  QueryBuilder(this._http, this._table);

  final InsforgeHttpClient _http;
  final String _table;

  /// Accumulated PostgREST query parameters (`column` -> `op.value`, plus
  /// `select`/`order`/`limit`/`offset`).
  final Map<String, dynamic> _params = <String, dynamic>{};

  String get _path => '/api/database/records/$_table';

  // ----- shaping -----

  /// Restricts the returned columns. Defaults to all columns (`*`).
  QueryBuilder select([String columns = '*']) {
    _params['select'] = columns;
    return this;
  }

  /// Orders results by [column]; descending when [ascending] is false.
  QueryBuilder order(String column, {bool ascending = true}) {
    _params['order'] = '$column.${ascending ? 'asc' : 'desc'}';
    return this;
  }

  /// Caps the number of rows returned.
  QueryBuilder limit(int count) {
    _params['limit'] = '$count';
    return this;
  }

  /// Skips [count] rows (pagination).
  QueryBuilder offset(int count) {
    _params['offset'] = '$count';
    return this;
  }

  /// Inclusive range pagination: `range(0, 9)` returns the first 10 rows.
  QueryBuilder range(int from, int to) {
    _params['offset'] = '$from';
    _params['limit'] = '${to - from + 1}';
    return this;
  }

  // ----- filters -----

  /// Equality filter (`column=eq.value`).
  QueryBuilder eq(String column, Object value) {
    _params[column] = 'eq.$value';
    return this;
  }

  /// Inequality filter (`column=neq.value`).
  QueryBuilder neq(String column, Object value) {
    _params[column] = 'neq.$value';
    return this;
  }

  /// Greater-than filter.
  QueryBuilder gt(String column, Object value) {
    _params[column] = 'gt.$value';
    return this;
  }

  /// Greater-than-or-equal filter.
  QueryBuilder gte(String column, Object value) {
    _params[column] = 'gte.$value';
    return this;
  }

  /// Less-than filter.
  QueryBuilder lt(String column, Object value) {
    _params[column] = 'lt.$value';
    return this;
  }

  /// Less-than-or-equal filter.
  QueryBuilder lte(String column, Object value) {
    _params[column] = 'lte.$value';
    return this;
  }

  /// Case-sensitive pattern match (`%` wildcard).
  QueryBuilder like(String column, String pattern) {
    _params[column] = 'like.$pattern';
    return this;
  }

  /// Case-insensitive pattern match (`%` wildcard).
  QueryBuilder ilike(String column, String pattern) {
    _params[column] = 'ilike.$pattern';
    return this;
  }

  /// `IS` filter: null when [value] is null, otherwise `is.true`/`is.false`.
  QueryBuilder isFilter(String column, bool? value) {
    final encoded = value == null ? 'null' : (value ? 'true' : 'false');
    _params[column] = 'is.$encoded';
    return this;
  }

  /// `IN` filter: `column=in.(a,b,c)`.
  QueryBuilder inFilter(String column, List<Object> values) {
    _params[column] = 'in.(${values.join(',')})';
    return this;
  }

  /// Contains filter (`cs`, PostgreSQL `@>`).
  QueryBuilder contains(String column, Object value) {
    _params[column] = 'cs.$value';
    return this;
  }

  /// Contained-by filter (`cd`, PostgreSQL `<@`).
  QueryBuilder containedBy(String column, Object value) {
    _params[column] = 'cd.$value';
    return this;
  }

  /// OR grouping using raw PostgREST expressions: `or('a.eq.1,b.eq.2')`.
  QueryBuilder or(String filters) {
    _params['or'] = '($filters)';
    return this;
  }

  /// Negates an operator: `not('status', 'eq', 'archived')` →
  /// `status=not.eq.archived`.
  QueryBuilder not(String column, String operator, Object? value) {
    final encoded = value == null ? 'null' : '$value';
    _params[column] = 'not.$operator.$encoded';
    return this;
  }

  /// Full-text search. [config] (when given) is wrapped in parentheses, e.g.
  /// `textSearch('body', 'q', type: TextSearchType.full, config: 'english')`
  /// → `body=fts(english).q`.
  QueryBuilder textSearch(
    String column,
    String query, {
    TextSearchType type = TextSearchType.plain,
    String? config,
  }) {
    final configPart = (config != null && config.isNotEmpty) ? '($config)' : '';
    _params[column] = '${type.value}$configPart.$query';
    return this;
  }

  /// Escape hatch for any PostgREST operator: `filter('id', 'in', '(1,2)')`.
  QueryBuilder filter(String column, String operator, Object value) {
    _params[column] = '$operator.$value';
    return this;
  }

  // ----- read terminal -----

  /// Executes the query and returns the rows as a list of JSON maps.
  Future<List<Map<String, dynamic>>> execute() async {
    final response = await _http.request<dynamic>(
      'GET',
      _path,
      queryParameters: _params,
    );
    return _asListOfMaps(response.data);
  }

  /// Helper used by terminals to coerce a JSON array response into maps.
  static List<Map<String, dynamic>> _asListOfMaps(Object? data) {
    if (data == null) return <Map<String, dynamic>>[];
    if (data is List) {
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
    throw InsforgeSerializationException(
      'Expected a JSON array but got ${data.runtimeType}',
    );
  }
}
```

- [ ] **Step 4: Create `database_client.dart` (minimal, just `from`)**

The test references `DatabaseClient`, so add it now. `rpc` is fleshed out in Task 8.

```dart
// packages/insforge_database/lib/src/database_client.dart
import 'package:insforge_core/insforge_core.dart';

import 'query_builder.dart';

/// Entry point for PostgREST-style database access.
///
/// Wraps a shared [InsforgeHttpClient]; all requests inherit its auth-header
/// injection, single-flight 401 refresh, and error mapping.
class DatabaseClient {
  DatabaseClient(this._http);

  final InsforgeHttpClient _http;

  /// Starts a query against [table].
  QueryBuilder from(String table) => QueryBuilder(_http, table);
}
```

- [ ] **Step 5: Export both**

Append to `packages/insforge_database/lib/insforge_database.dart`:

```dart
export 'src/query_builder.dart';
export 'src/database_client.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/insforge_database && dart test test/query_filters_test.dart`
Expected: PASS (all filter/shaping/execute tests).

- [ ] **Step 7: Commit**

```bash
git add packages/insforge_database/lib/src/query_builder.dart packages/insforge_database/lib/src/database_client.dart packages/insforge_database/lib/insforge_database.dart packages/insforge_database/test/query_filters_test.dart
git commit -m "feat(database): QueryBuilder filters, shaping, and execute terminal"
```

---

## Task 5: Read terminals — `executeAs`, `single`, `count`

**Files:**
- Modify: `packages/insforge_database/lib/src/query_builder.dart`
- Test: `packages/insforge_database/test/query_terminal_test.dart`

`single()` sets `Accept: application/vnd.pgrst.object+json` and returns one map. `executeAs<T>` maps each row via a `fromJson`. `count()` issues a GET with `Prefer: count=<token>` (and `limit=0` so no rows are scanned beyond counting) and reads `X-Total-Count`, falling back to the `/`-suffix of `Content-Range`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_database/test/query_terminal_test.dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_database && dart test test/query_terminal_test.dart`
Expected: FAIL — `executeAs`/`single`/`count` not defined.

- [ ] **Step 3: Add the terminals to `query_builder.dart`**

Insert these methods inside the `QueryBuilder` class (e.g. directly after `execute()`):

```dart
  /// Executes the query and maps each row with [fromJson].
  Future<List<T>> executeAs<T>(T Function(Map<String, dynamic>) fromJson) async {
    final rows = await execute();
    return rows.map(fromJson).toList();
  }

  /// Executes the query expecting exactly one row.
  ///
  /// Sets `Accept: application/vnd.pgrst.object+json` so the server returns a
  /// single object (HTTP 406 → an [InsforgeHttpException] from the core client).
  Future<Map<String, dynamic>> single() async {
    final response = await _http.request<dynamic>(
      'GET',
      _path,
      queryParameters: _params,
      headers: <String, String>{
        'Accept': 'application/vnd.pgrst.object+json',
      },
    );
    final data = response.data;
    if (data is Map<dynamic, dynamic>) {
      return Map<String, dynamic>.from(data);
    }
    throw InsforgeSerializationException(
      'single() expected a JSON object but got ${data.runtimeType}',
    );
  }

  /// Returns the number of rows matching the current filters.
  ///
  /// Issues `GET` with `Prefer: count=<type>` and `limit=0`, then reads
  /// `X-Total-Count`, falling back to the total in `Content-Range` (`0-0/123`).
  Future<int> count({CountType type = CountType.exact}) async {
    final params = <String, dynamic>{..._params, 'limit': '0'};
    final response = await _http.request<dynamic>(
      'GET',
      _path,
      queryParameters: params,
      headers: <String, String>{'Prefer': 'count=${type.preferToken}'},
    );
    final headers = response.headers;
    final totalHeader = headers.value('X-Total-Count');
    if (totalHeader != null) {
      return int.tryParse(totalHeader) ?? 0;
    }
    final contentRange = headers.value('Content-Range');
    if (contentRange != null && contentRange.contains('/')) {
      return int.tryParse(contentRange.split('/').last) ?? 0;
    }
    return 0;
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_database && dart test test/query_terminal_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_database/lib/src/query_builder.dart packages/insforge_database/test/query_terminal_test.dart
git commit -m "feat(database): add executeAs, single, and count terminals"
```

---

## Task 6: Mutation builders — `insert`, `update`, `delete`

**Files:**
- Create: `packages/insforge_database/lib/src/mutation_builder.dart`
- Modify: `packages/insforge_database/lib/src/query_builder.dart` (add `insert`/`update`/`delete`)
- Test: `packages/insforge_database/test/mutation_test.dart`
- Modify: `packages/insforge_database/lib/insforge_database.dart`

`insert` always sends a JSON **array** body (records.yaml requires it), even for a single map. `update`/`delete` carry the accumulated filters as query params. Without `.select()` the server returns `[]`; `.select()` adds `Prefer: return=representation` so callers get the affected rows back. Each mutation builder's terminal is `execute()` returning `List<Map<String, dynamic>>`.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_database/test/mutation_test.dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_database && dart test test/mutation_test.dart`
Expected: FAIL — `insert`/`update`/`delete` not defined.

- [ ] **Step 3: Write `mutation_builder.dart`**

```dart
// packages/insforge_database/lib/src/mutation_builder.dart
import 'package:insforge_core/insforge_core.dart';

/// Shared response coercion + representation flag for mutation builders.
abstract class _MutationBuilderBase {
  _MutationBuilderBase(this.http, this.path);

  final InsforgeHttpClient http;
  final String path;

  bool returnRepresentation = false;

  /// Coerces a JSON-array response into a list of maps (empty when no body).
  static List<Map<String, dynamic>> asRows(Object? data) {
    if (data == null) return <Map<String, dynamic>>[];
    if (data is List) {
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
    if (data is String && data.isEmpty) return <Map<String, dynamic>>[];
    throw InsforgeSerializationException(
      'Expected a JSON array but got ${data.runtimeType}',
    );
  }

  Map<String, String> get preferHeaders => returnRepresentation
      ? <String, String>{'Prefer': 'return=representation'}
      : <String, String>{};
}

/// Builds and executes a record insert (`POST`).
///
/// The body is always sent as a JSON array (the records API requires it).
/// Call [select] before [execute] to receive the inserted rows.
class InsertBuilder extends _MutationBuilderBase {
  InsertBuilder(super.http, super.path, this._values);

  final List<Map<String, dynamic>> _values;

  /// Requests the inserted rows back (`Prefer: return=representation`).
  InsertBuilder select() {
    returnRepresentation = true;
    return this;
  }

  /// Performs the insert. Returns `[]` unless [select] was called.
  Future<List<Map<String, dynamic>>> execute() async {
    final response = await http.request<dynamic>(
      'POST',
      path,
      data: _values,
      headers: preferHeaders,
    );
    return _MutationBuilderBase.asRows(response.data);
  }
}

/// Builds and executes a record update (`PATCH`) over the captured filters.
class UpdateBuilder extends _MutationBuilderBase {
  UpdateBuilder(super.http, super.path, this._values, this._filters);

  final Map<String, dynamic> _values;
  final Map<String, dynamic> _filters;

  /// Requests the updated rows back (`Prefer: return=representation`).
  UpdateBuilder select() {
    returnRepresentation = true;
    return this;
  }

  /// Performs the update. Returns `[]` unless [select] was called.
  Future<List<Map<String, dynamic>>> execute() async {
    final response = await http.request<dynamic>(
      'PATCH',
      path,
      data: _values,
      queryParameters: _filters,
      headers: preferHeaders,
    );
    return _MutationBuilderBase.asRows(response.data);
  }
}

/// Builds and executes a record delete (`DELETE`) over the captured filters.
class DeleteBuilder extends _MutationBuilderBase {
  DeleteBuilder(super.http, super.path, this._filters);

  final Map<String, dynamic> _filters;

  /// Requests the deleted rows back (`Prefer: return=representation`).
  DeleteBuilder select() {
    returnRepresentation = true;
    return this;
  }

  /// Performs the delete. Returns `[]` unless [select] was called.
  Future<List<Map<String, dynamic>>> execute() async {
    final response = await http.request<dynamic>(
      'DELETE',
      path,
      queryParameters: _filters,
      headers: preferHeaders,
    );
    return _MutationBuilderBase.asRows(response.data);
  }
}
```

- [ ] **Step 4: Add `insert`/`update`/`delete` to `QueryBuilder`**

Add these methods inside the `QueryBuilder` class (e.g. after the read terminals), and add the import at the top of `query_builder.dart`.

At the top of `packages/insforge_database/lib/src/query_builder.dart`, add:

```dart
import 'mutation_builder.dart';
```

Inside the class:

```dart
  // ----- mutations -----

  /// Inserts one map or a list of maps. The body is always sent as an array.
  InsertBuilder insert(dynamic values) {
    final rows = _toRows(values);
    return InsertBuilder(_http, _path, rows);
  }

  /// Updates rows matching the accumulated filters with [values].
  UpdateBuilder update(Map<String, dynamic> values) {
    return UpdateBuilder(_http, _path, values, _filterParams());
  }

  /// Deletes rows matching the accumulated filters.
  DeleteBuilder delete() {
    return DeleteBuilder(_http, _path, _filterParams());
  }

  /// Normalizes a single map or list-of-maps into a `List<Map>`.
  static List<Map<String, dynamic>> _toRows(dynamic values) {
    if (values is Map<String, dynamic>) {
      return <Map<String, dynamic>>[values];
    }
    if (values is List) {
      return values
          .whereType<Map<dynamic, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
    throw ArgumentError(
      'insert/upsert expects a Map<String, dynamic> or List<Map<String, dynamic>>',
    );
  }

  /// The accumulated params with shaping keys removed — i.e. just the filters
  /// that select which rows a mutation affects.
  Map<String, dynamic> _filterParams() {
    const shaping = <String>{'select', 'order', 'limit', 'offset'};
    return <String, dynamic>{
      for (final entry in _params.entries)
        if (!shaping.contains(entry.key)) entry.key: entry.value,
    };
  }
```

- [ ] **Step 5: Export the mutation builders**

Append to `packages/insforge_database/lib/insforge_database.dart`:

```dart
export 'src/mutation_builder.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/insforge_database && dart test test/mutation_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 7: Commit**

```bash
git add packages/insforge_database/lib/src/mutation_builder.dart packages/insforge_database/lib/src/query_builder.dart packages/insforge_database/lib/insforge_database.dart packages/insforge_database/test/mutation_test.dart
git commit -m "feat(database): add insert/update/delete mutation builders"
```

---

## Task 7: Upsert builder

**Files:**
- Modify: `packages/insforge_database/lib/src/mutation_builder.dart` (add `UpsertBuilder`)
- Modify: `packages/insforge_database/lib/src/query_builder.dart` (add `upsert`)
- Test: `packages/insforge_database/test/upsert_test.dart`

`upsert` is a `POST` like insert (array body) but adds `Prefer: resolution=merge-duplicates` (or `resolution=ignore-duplicates` when `ignoreDuplicates: true`) and, when `onConflict` is supplied, an `on_conflict` query parameter. `.select()` adds `return=representation`, joined into the same `Prefer` header.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_database/test/upsert_test.dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_database && dart test test/upsert_test.dart`
Expected: FAIL — `upsert` not defined.

- [ ] **Step 3: Add `UpsertBuilder` to `mutation_builder.dart`**

Append this class to `packages/insforge_database/lib/src/mutation_builder.dart`:

```dart
/// Builds and executes an upsert (`POST` with `resolution=` Prefer).
///
/// Inserts rows, merging (or ignoring) on conflict. Supply [onConflict] to
/// target specific columns; call [select] to receive the affected rows.
class UpsertBuilder extends _MutationBuilderBase {
  UpsertBuilder(
    super.http,
    super.path,
    this._values, {
    String? onConflict,
    bool ignoreDuplicates = false,
  })  : _onConflict = onConflict,
        _ignoreDuplicates = ignoreDuplicates;

  final List<Map<String, dynamic>> _values;
  final String? _onConflict;
  final bool _ignoreDuplicates;

  /// Requests the upserted rows back (`return=representation`).
  UpsertBuilder select() {
    returnRepresentation = true;
    return this;
  }

  /// Performs the upsert. Returns `[]` unless [select] was called.
  Future<List<Map<String, dynamic>>> execute() async {
    final prefer = <String>[
      _ignoreDuplicates
          ? 'resolution=ignore-duplicates'
          : 'resolution=merge-duplicates',
      if (returnRepresentation) 'return=representation',
    ];
    final query = <String, dynamic>{
      if (_onConflict != null) 'on_conflict': _onConflict,
    };
    final response = await http.request<dynamic>(
      'POST',
      path,
      data: _values,
      queryParameters: query.isEmpty ? null : query,
      headers: <String, String>{'Prefer': prefer.join(',')},
    );
    return _MutationBuilderBase.asRows(response.data);
  }
}
```

- [ ] **Step 4: Add `upsert` to `QueryBuilder`**

Add this method inside the `QueryBuilder` class, alongside the other mutations:

```dart
  /// Inserts rows, updating (or ignoring) on conflict. The body is sent as an
  /// array. Pass [onConflict] to target columns and [ignoreDuplicates] to skip
  /// rather than merge conflicting rows.
  UpsertBuilder upsert(
    dynamic values, {
    String? onConflict,
    bool ignoreDuplicates = false,
  }) {
    return UpsertBuilder(
      _http,
      _path,
      _toRows(values),
      onConflict: onConflict,
      ignoreDuplicates: ignoreDuplicates,
    );
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_database && dart test test/upsert_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_database/lib/src/mutation_builder.dart packages/insforge_database/lib/src/query_builder.dart packages/insforge_database/test/upsert_test.dart
git commit -m "feat(database): add upsert builder with resolution Prefer + on_conflict"
```

---

## Task 8: RPC builder + `DatabaseClient.rpc`

**Files:**
- Create: `packages/insforge_database/lib/src/rpc_builder.dart`
- Modify: `packages/insforge_database/lib/src/database_client.dart` (add `rpc`)
- Test: `packages/insforge_database/test/rpc_test.dart`
- Modify: `packages/insforge_database/lib/insforge_database.dart`

RPC routes to `/api/database/rpc/{fn}`. With no args it is a `GET`; with args it is a `POST` carrying the args as the JSON body. `execute()` returns the decoded JSON (a `List` of rows or a scalar/map, surfaced as `dynamic`).

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_database && dart test test/rpc_test.dart`
Expected: FAIL — `rpc` / `RpcBuilder` not defined.

- [ ] **Step 3: Write `rpc_builder.dart`**

```dart
// packages/insforge_database/lib/src/rpc_builder.dart
import 'package:insforge_core/insforge_core.dart';

/// Calls a PostgreSQL function (RPC) at `/api/database/rpc/{fn}`.
///
/// Routes to `GET` when there are no arguments and `POST` (with the args as a
/// JSON body) otherwise. [execute] returns the decoded JSON response.
class RpcBuilder {
  RpcBuilder(this._http, this._fn, this._args);

  final InsforgeHttpClient _http;
  final String _fn;
  final Map<String, dynamic>? _args;

  String get _path => '/api/database/rpc/$_fn';

  /// Invokes the function and returns its decoded JSON result.
  Future<dynamic> execute() async {
    final hasArgs = _args != null && _args.isNotEmpty;
    final response = await _http.request<dynamic>(
      hasArgs ? 'POST' : 'GET',
      _path,
      data: hasArgs ? _args : null,
    );
    return response.data;
  }
}
```

- [ ] **Step 4: Add `rpc` to `DatabaseClient`**

In `packages/insforge_database/lib/src/database_client.dart`, add the import and the method.

At the top, alongside the existing imports:

```dart
import 'rpc_builder.dart';
```

Inside the `DatabaseClient` class, after `from`:

```dart
  /// Starts an RPC call to the database function [fn]. Provide [args] to send a
  /// `POST` with a JSON body; omit them for a `GET`.
  RpcBuilder rpc(String fn, {Map<String, dynamic>? args}) {
    return RpcBuilder(_http, fn, args);
  }
```

- [ ] **Step 5: Export it**

Append to `packages/insforge_database/lib/insforge_database.dart`:

```dart
export 'src/rpc_builder.dart';
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd packages/insforge_database && dart test test/rpc_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 7: Commit**

```bash
git add packages/insforge_database/lib/src/rpc_builder.dart packages/insforge_database/lib/src/database_client.dart packages/insforge_database/lib/insforge_database.dart packages/insforge_database/test/rpc_test.dart
git commit -m "feat(database): add RpcBuilder with GET/POST routing"
```

---

## Task 9: Full suite + analyze + CI

**Files:**
- Modify: `.github/workflows/ci.yaml` (add a database test step)

- [ ] **Step 1: Run the full package suite and analyzer**

Run: `cd packages/insforge_database && dart test && dart analyze`
Expected: all tests PASS across every test file; "No issues found!"

- [ ] **Step 2: Add a CI step for the package**

In `.github/workflows/ci.yaml` (created in Plan 1), append a test step after the existing per-package steps:

```yaml
      - name: Test insforge_database
        working-directory: packages/insforge_database
        run: dart test
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci(database): run insforge_database tests"
```

---

## Self-Review Notes

- **Spec coverage (design §4.3):** `DatabaseClient(http)` with `from` (Task 4) and `rpc` (Task 8). `QueryBuilder` filters `eq/neq/gt/gte/lt/lte/like/ilike/isFilter/inFilter/contains/containedBy/or/not/textSearch/filter` and shaping `select/order/limit/offset/range` (Task 4); terminals `execute/executeAs/single/count` (Tasks 4–5). Mutations `insert/update/delete` (Task 6) and `upsert` (Task 7), each with `.select()` → `Prefer: return=representation` and a `List<Map>` `execute()`. Enums `CountType` and `TextSearchType` (Task 2). Endpoints `/api/database/records/{table}` and `/api/database/rpc/{fn}` confirmed against `records.yaml`. Covered.
- **Confirmed wire details (from `records.yaml` + Kotlin/Swift SDKs):** filters are `column=op.value` query params; insert/upsert bodies MUST be JSON arrays (records.yaml `minItems: 1`, "Request body MUST be an array"); without `Prefer: return=representation` POST/PATCH return `[]` and DELETE returns 204 — hence opt-in via `.select()`. `TextSearchType` = `fts`/`plfts`(default)/`phfts`/`wfts`. `CountType` → `Prefer: count=exact|planned|estimated`. Upsert → `Prefer: resolution=merge-duplicates|ignore-duplicates` (+ `return=representation` joined with a comma) and an `on_conflict` query param. `single()` → `Accept: application/vnd.pgrst.object+json` (406 surfaces as the core client's `InsforgeHttpException`). `count()` reads `X-Total-Count`, falling back to the `/`-suffix of `Content-Range`.
- **Design decisions:** (1) **Mutable builder returning `this`** — chosen over an immutable copy-on-write builder to keep the implementation small and mirror the Kotlin `TableQuery`; a consequence is that repeating a filter on the same column is last-write-wins (documented in the test), matching the Kotlin map-backed behavior. (2) Filter accumulation lives in one `_params` map; mutations strip the shaping keys (`select/order/limit/offset`) via `_filterParams()` so `update`/`delete` carry only row-selection filters. (3) `insert`/`upsert` accept `dynamic` (a single `Map` or a `List<Map>`) and always normalize to an array body. (4) Mutation terminals return `List<Map<String,dynamic>>` and tolerate an empty body (`[]`/`204`) so callers who skip `.select()` get an empty list rather than an error.
- **Core API reused (from Plan 1):** `InsforgeHttpClient` (`request`, `.dio`, `.headers` on responses via dio), `InsforgeSerializationException`. Auth-header injection, single-flight 401 refresh, and HTTP-error mapping are inherited from the core client — this package adds no transport logic of its own.
- **Type names later plans/sample must import:** `DatabaseClient`, `QueryBuilder`, `InsertBuilder`, `UpdateBuilder`, `DeleteBuilder`, `UpsertBuilder`, `RpcBuilder`, `CountType`, `TextSearchType` — keep these stable for the umbrella (Plan 7) and the sample app.
</content>
</invoke>
