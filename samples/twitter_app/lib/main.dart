// samples/twitter_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import 'providers.dart';
import 'screens/auth_screen.dart';
import 'screens/feed_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  // Restore a persisted session before the first frame.
  await container.read(insforgeServiceProvider).restore();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TwitterApp(),
    ),
  );
}

class TwitterApp extends StatelessWidget {
  const TwitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InsForge Twitter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Shows the feed when signed in, the auth screen otherwise.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      data: (AuthState state) =>
          state.session != null ? const FeedScreen() : const AuthScreen(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (Object e, _) =>
          Scaffold(body: Center(child: Text('Auth error: $e'))),
    );
  }
}
