// packages/insforge_auth/lib/src/auth_options.dart
import 'enums.dart';

/// Tunable behavior for [AuthClient].
class AuthOptions {
  const AuthOptions({
    this.autoRefreshToken = true,
    this.clientType = ClientType.mobile,
  });

  /// When true, the client registers a refresh callback with the HTTP client
  /// (reactive 401 refresh) and proactively refreshes near token expiry.
  final bool autoRefreshToken;

  /// Client type sent as `client_type` on token-issuing calls. Defaults to
  /// [ClientType.mobile] so refresh tokens are returned in the body.
  final ClientType clientType;
}
