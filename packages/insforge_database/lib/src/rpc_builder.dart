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
