// packages/insforge_auth/lib/src/models/auth_response.dart
import 'session.dart';
import 'user.dart';

/// Response from a token-issuing call (signin, verify-email, refresh, oauth
/// exchange): the user plus an access token and optional refresh token.
class AuthResponse {
  const AuthResponse({
    required this.user,
    required this.accessToken,
    this.refreshToken,
  });

  final User user;
  final String accessToken;
  final String? refreshToken;

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: User.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
    );
  }

  /// Builds a [Session] from this response.
  Session toSession() => Session(
        accessToken: accessToken,
        refreshToken: refreshToken,
        user: user,
      );
}
