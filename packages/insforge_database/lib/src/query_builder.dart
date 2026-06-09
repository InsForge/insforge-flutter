// packages/insforge_database/lib/src/query_builder.dart
import 'package:insforge_core/insforge_core.dart';

import 'enums.dart';
import 'mutation_builder.dart';

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
