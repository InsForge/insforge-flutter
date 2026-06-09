// packages/insforge_auth/lib/src/models/sign_up_response.dart
import 'session.dart';
import 'user.dart';

/// Response from `POST /api/auth/users`.
///
/// When email verification is required, the backend omits the session fields:
/// [user], [accessToken], and [refreshToken] are all null and
/// [requireEmailVerification] is true; the caller must complete the
/// verification flow before a session exists. [user] is therefore nullable —
/// it is only present on an immediate-session signup (verification disabled).
class SignUpResponse {
  const SignUpResponse({
    this.user,
    this.accessToken,
    this.refreshToken,
    this.requireEmailVerification = false,
  });

  /// The created user, or null when email verification is required (the server
  /// returns no user object until the account is verified).
  final User? user;
  final String? accessToken;
  final String? refreshToken;
  final bool requireEmailVerification;

  /// True when the signup yielded an immediate session (an access token).
  bool get hasSession => accessToken != null;

  factory SignUpResponse.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    return SignUpResponse(
      user: rawUser is Map
          ? User.fromJson(Map<String, dynamic>.from(rawUser))
          : null,
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      requireEmailVerification:
          json['requireEmailVerification'] as bool? ?? false,
    );
  }

  /// Builds a [Session] when this response carries both an access token and a
  /// user (i.e. an immediate-session signup), else null.
  Session? toSession() {
    final token = accessToken;
    final sessionUser = user;
    if (token == null || sessionUser == null) return null;
    return Session(
      accessToken: token,
      refreshToken: refreshToken,
      user: sessionUser,
    );
  }
}
