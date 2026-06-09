// packages/insforge_auth/lib/src/models/session.dart
import 'user.dart';

/// A signed-in session: the access token (+ optional refresh token) and the
/// associated [User].
class Session {
  const Session({
    required this.accessToken,
    required this.user,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;
  final User user;

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      user: User.fromJson(
        Map<String, dynamic>.from(json['user'] as Map),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'accessToken': accessToken,
      if (refreshToken != null) 'refreshToken': refreshToken,
      'user': user.toJson(),
    };
  }

  Session copyWith({String? accessToken, String? refreshToken, User? user}) {
    return Session(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      user: user ?? this.user,
    );
  }
}
