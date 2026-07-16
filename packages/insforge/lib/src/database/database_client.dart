// packages/insforge_database/lib/src/database_client.dart
import 'package:insforge/insforge.dart';

/// Entry point for PostgREST-style database access.
///
/// Wraps a shared [InsforgeHttpClient]; all requests inherit its auth-header
/// injection, single-flight 401 refresh, and error mapping.
class DatabaseClient {
  DatabaseClient(this._http);

  final InsforgeHttpClient _http;

  /// Starts a query against [table].
  QueryBuilder from(String table) => QueryBuilder(_http, table);

  /// Starts an RPC call to the database function [fn]. Provide [args] to send a
  /// `POST` with a JSON body; omit them for a `GET`.
  RpcBuilder rpc(String fn, {Map<String, dynamic>? args}) {
    return RpcBuilder(_http, fn, args);
  }
}
