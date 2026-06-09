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
