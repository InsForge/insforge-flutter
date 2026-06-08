// packages/insforge_auth/lib/src/models/sign_up_response.dart
import 'session.dart';
import 'user.dart';

/// Response from `POST /api/auth/users`.
///
/// When email verification is required, [accessToken] and [refreshToken] are
/// null and [requireEmailVerification] is true; the caller must complete the
/// verification flow before a session exists.
class SignUpResponse {
  const SignUpResponse({
    required this.user,
    this.accessToken,
    this.refreshToken,
    this.requireEmailVerification = false,
  });

  final User user;
  final String? accessToken;
  final String? refreshToken;
  final bool requireEmailVerification;

  /// True when the signup yielded an immediate session (an access token).
  bool get hasSession => accessToken != null;

  factory SignUpResponse.fromJson(Map<String, dynamic> json) {
    return SignUpResponse(
      user: User.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      requireEmailVerification:
          json['requireEmailVerification'] as bool? ?? false,
    );
  }

  /// Builds a [Session] when this response carries an access token, else null.
  Session? toSession() {
    final token = accessToken;
    if (token == null) return null;
    return Session(
      accessToken: token,
      refreshToken: refreshToken,
      user: user,
    );
  }
}
