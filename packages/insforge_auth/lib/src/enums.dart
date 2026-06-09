// packages/insforge_auth/lib/src/enums.dart

/// OAuth providers supported by the InsForge backend.
///
/// [wireName] is the value used in the `/api/auth/oauth/{provider}` path.
enum OAuthProvider {
  google('google'),
  github('github'),
  discord('discord'),
  linkedin('linkedin'),
  facebook('facebook'),
  instagram('instagram'),
  tiktok('tiktok'),
  apple('apple'),
  x('x'),
  spotify('spotify'),
  microsoft('microsoft');

  const OAuthProvider(this.wireName);

  /// The provider key sent on the wire (e.g. `google`).
  final String wireName;
}

/// Client type sent as the `client_type` query parameter on token-issuing
/// calls. Mobile/desktop/server return the refresh token in the body; web
/// uses an httpOnly cookie. The Flutter SDK defaults to [ClientType.mobile].
enum ClientType {
  web('web'),
  mobile('mobile'),
  desktop('desktop'),
  server('server');

  const ClientType(this.wireName);

  /// The value sent in the `client_type` query parameter.
  final String wireName;
}

/// Lifecycle events emitted on [AuthClient.onAuthStateChange].
enum AuthChangeEvent {
  /// A new session was established (sign-up with session, sign-in, verify,
  /// or OAuth exchange).
  signedIn,

  /// The session was cleared.
  signedOut,

  /// The access token was refreshed; the session is otherwise unchanged.
  tokenRefreshed,

  /// The current user's profile/details changed (e.g. `updateProfile`).
  userUpdated,
}
