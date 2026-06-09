// packages/insforge_auth/lib/src/auth_state.dart
import 'enums.dart';
import 'models/session.dart';

/// Emitted on [AuthClient.onAuthStateChange]. Carries the lifecycle [event]
/// and the current [session] (null after sign-out).
class AuthState {
  const AuthState(this.event, this.session);

  final AuthChangeEvent event;
  final Session? session;
}
