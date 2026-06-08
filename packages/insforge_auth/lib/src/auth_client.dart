// packages/insforge_auth/lib/src/auth_client.dart
import 'dart:async';
import 'dart:convert';

import 'package:insforge_core/insforge_core.dart';

import 'auth_options.dart';
import 'auth_state.dart';
import 'enums.dart';
import 'jwt.dart';
import 'models/auth_response.dart';
import 'models/profile.dart';
import 'models/reset_token_response.dart';
import 'models/session.dart';
import 'models/sign_up_response.dart';
import 'models/user.dart';

/// Storage key for the persisted refresh token.
const String kRefreshTokenKey = 'insforge_refresh_token';

/// Storage key for the persisted access token.
const String kAccessTokenKey = 'insforge_access_token';

/// Storage key for the persisted serialized [User].
const String kUserKey = 'insforge_user';

/// Refresh proactively when the access token expires within this leeway.
const Duration kProactiveRefreshLeeway = Duration(seconds: 30);

/// High-level authentication client.
///
/// Wraps a shared [InsforgeHttpClient] and a [SessionStorage]. Writes the
/// http client's access token, registers its refresh callback, persists the
/// session, and broadcasts [AuthState] changes.
class AuthClient {
  AuthClient(
    this._http,
    this._storage, {
    AuthOptions? options,
  }) : _options = options ?? const AuthOptions() {
    if (_options.autoRefreshToken) {
      _http.registerRefreshCallback(_refreshForHttpClient);
    }
  }

  final InsforgeHttpClient _http;
  final SessionStorage _storage;
  final AuthOptions _options;

  final StreamController<AuthState> _stateController =
      StreamController<AuthState>.broadcast();

  Session? _currentSession;

  /// Broadcast stream of authentication lifecycle changes.
  Stream<AuthState> get onAuthStateChange => _stateController.stream;

  /// The currently signed-in user, or null.
  User? get currentUser => _currentSession?.user;

  /// The current session, or null when signed out.
  Session? get currentSession => _currentSession;

  /// The `client_type` query parameter applied to token-issuing calls.
  Map<String, dynamic> get _clientTypeQuery =>
      <String, dynamic>{'client_type': _options.clientType.wireName};

  // ---------------------------------------------------------------------------
  // Email / password
  // ---------------------------------------------------------------------------

  /// Signs in with email + password. Persists and emits on success.
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/sessions',
      data: <String, dynamic>{'email': email, 'password': password},
      queryParameters: _clientTypeQuery,
    );
    final response = AuthResponse.fromJson(res.data!);
    await _applySession(response.toSession(), AuthChangeEvent.signedIn);
    return response;
  }

  /// Registers a new user. When email verification is disabled the response
  /// carries a session, which is persisted and emitted; otherwise no session
  /// is established yet.
  Future<SignUpResponse> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/users',
      data: <String, dynamic>{
        'email': email,
        'password': password,
        if (name != null) 'name': name,
      },
      queryParameters: _clientTypeQuery,
    );
    final response = SignUpResponse.fromJson(res.data!);
    final session = response.toSession();
    if (session != null) {
      await _applySession(session, AuthChangeEvent.signedIn);
    }
    return response;
  }

  /// Signs out: best-effort backend logout, then clears in-memory and
  /// persisted session and emits [AuthChangeEvent.signedOut].
  Future<void> signOut() async {
    try {
      await _http.request<dynamic>('POST', '/api/auth/logout');
    } catch (_) {
      // Ignore backend logout failures; local state is cleared regardless.
    }
    _currentSession = null;
    _http.accessToken = null;
    await _clearPersisted();
    _stateController.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  // ---------------------------------------------------------------------------
  // Session application + persistence (shared by all auth flows)
  // ---------------------------------------------------------------------------

  Future<void> _applySession(Session session, AuthChangeEvent event) async {
    _currentSession = session;
    _http.accessToken = session.accessToken;
    await _persist(session);
    _stateController.add(AuthState(event, session));
  }

  Future<void> _persist(Session session) async {
    await _storage.write(kAccessTokenKey, session.accessToken);
    final refresh = session.refreshToken;
    if (refresh != null) {
      await _storage.write(kRefreshTokenKey, refresh);
    }
    await _storage.write(kUserKey, jsonEncode(session.user.toJson()));
  }

  Future<void> _clearPersisted() async {
    await _storage.delete(kAccessTokenKey);
    await _storage.delete(kRefreshTokenKey);
    await _storage.delete(kUserKey);
  }

  // ---------------------------------------------------------------------------
  // Refresh callback for the HTTP client (reactive 401 refresh)
  // ---------------------------------------------------------------------------

  Future<String> _refreshForHttpClient() async {
    final response = await refreshAccessToken();
    return response.accessToken;
  }

  /// Refreshes the access token using the persisted refresh token. Persists the
  /// new tokens and emits [AuthChangeEvent.tokenRefreshed].
  Future<AuthResponse> refreshAccessToken() async {
    final refreshToken = await _storage.read(kRefreshTokenKey);
    if (refreshToken == null) {
      throw InsforgeAuthException('No refresh token available');
    }
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/refresh',
      data: <String, dynamic>{'refreshToken': refreshToken},
      queryParameters: _clientTypeQuery,
    );
    final response = AuthResponse.fromJson(res.data!);
    await _applySession(response.toSession(), AuthChangeEvent.tokenRefreshed);
    return response;
  }

  /// Fetches the currently authenticated user from the access token.
  Future<User> getCurrentUser() async {
    final res = await _http.request<Map<String, dynamic>>(
      'GET',
      '/api/auth/sessions/current',
    );
    return User.fromJson(Map<String, dynamic>.from(res.data!['user'] as Map));
  }

  // ---------------------------------------------------------------------------
  // Email verification
  // ---------------------------------------------------------------------------

  /// Sends (or resends) a verification email/code to [email].
  Future<void> sendVerificationEmail(String email) async {
    await _http.request<dynamic>(
      'POST',
      '/api/auth/email/send-verification',
      data: <String, dynamic>{'email': email},
    );
  }

  /// Verifies an email with a 6-digit [otp], establishing a session.
  Future<AuthResponse> verifyEmail({
    String? email,
    required String otp,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/email/verify',
      data: <String, dynamic>{
        if (email != null) 'email': email,
        'otp': otp,
      },
      queryParameters: _clientTypeQuery,
    );
    final response = AuthResponse.fromJson(res.data!);
    await _applySession(response.toSession(), AuthChangeEvent.signedIn);
    return response;
  }

  // ---------------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------------

  /// Sends a password-reset email/code to [email].
  Future<void> sendPasswordReset(String email) async {
    await _http.request<dynamic>(
      'POST',
      '/api/auth/email/send-reset-password',
      data: <String, dynamic>{'email': email},
    );
  }

  /// Exchanges a 6-digit reset [code] for a single-use reset token.
  Future<ResetTokenResponse> exchangeResetPasswordToken({
    required String email,
    required String code,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/email/exchange-reset-password-token',
      data: <String, dynamic>{'email': email, 'code': code},
    );
    return ResetTokenResponse.fromJson(res.data!);
  }

  /// Resets the password using a reset [otp] (the token from
  /// [exchangeResetPasswordToken] or a magic-link token).
  Future<void> resetPassword({
    required String otp,
    required String newPassword,
  }) async {
    await _http.request<dynamic>(
      'POST',
      '/api/auth/email/reset-password',
      data: <String, dynamic>{'newPassword': newPassword, 'otp': otp},
    );
  }

  // ---------------------------------------------------------------------------
  // OAuth (PKCE)
  // ---------------------------------------------------------------------------

  /// Requests the provider authorization URL for a PKCE flow. The app should
  /// open the returned URL in a browser, then pass the callback URI to
  /// [handleOAuthCallback] along with the original [PkceHelper] verifier.
  Future<String> getOAuthUrl({
    required OAuthProvider provider,
    required String redirectUri,
    required String codeChallenge,
  }) async {
    final res = await _http.request<Map<String, dynamic>>(
      'GET',
      '/api/auth/oauth/${provider.wireName}',
      queryParameters: <String, dynamic>{
        'redirect_uri': redirectUri,
        'code_challenge': codeChallenge,
      },
    );
    return res.data!['authUrl'] as String;
  }

  /// Completes a PKCE OAuth flow: extracts `insforge_code` from [callbackUri],
  /// exchanges it (with [codeVerifier]) for a session, and persists/emits.
  Future<AuthResponse> handleOAuthCallback(
    Uri callbackUri,
    String codeVerifier,
  ) async {
    final code = callbackUri.queryParameters['insforge_code'];
    if (code == null || code.isEmpty) {
      throw InsforgeAuthException(
        'OAuth callback is missing the insforge_code parameter',
      );
    }
    final res = await _http.request<Map<String, dynamic>>(
      'POST',
      '/api/auth/oauth/exchange',
      data: <String, dynamic>{'code': code, 'code_verifier': codeVerifier},
      queryParameters: _clientTypeQuery,
    );
    final response = AuthResponse.fromJson(res.data!);
    await _applySession(response.toSession(), AuthChangeEvent.signedIn);
    return response;
  }

  /// Releases the broadcast stream controller.
  Future<void> dispose() => _stateController.close();
}
