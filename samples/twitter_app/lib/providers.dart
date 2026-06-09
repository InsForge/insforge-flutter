// samples/twitter_app/lib/providers.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge_flutter/insforge_flutter.dart';

import 'services/insforge_service.dart';

/// The app-wide InsForge service (owns the client + OAuth flow).
final insforgeServiceProvider = Provider<InsforgeService>((ref) {
  final service = InsforgeService();
  ref.onDispose(service.dispose);
  return service;
});

/// Convenience accessor for the underlying client.
final insforgeClientProvider = Provider<InsforgeClient>((ref) {
  return ref.watch(insforgeServiceProvider).client;
});

/// The auth client.
final authClientProvider = Provider<AuthClient>((ref) {
  return ref.watch(insforgeClientProvider).auth;
});

/// Streams auth lifecycle changes. The UI watches this to gate signed-in vs
/// signed-out screens. Seeded with the current session so the first build
/// reflects a restored session.
final authStateProvider = StreamProvider<AuthState>((ref) {
  final auth = ref.watch(authClientProvider);
  final controller = StreamController<AuthState>();
  // Emit the current state immediately, then forward live changes.
  final current = auth.currentSession;
  controller.add(
    AuthState(
      current != null ? AuthChangeEvent.signedIn : AuthChangeEvent.signedOut,
      current,
    ),
  );
  final sub = auth.onAuthStateChange.listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The currently signed-in user, or null.
final currentUserProvider = Provider<User?>((ref) {
  final state = ref.watch(authStateProvider);
  return state.maybeWhen(
    data: (AuthState s) => s.session?.user,
    orElse: () => null,
  );
});
