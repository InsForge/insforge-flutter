// packages/insforge_flutter/lib/src/insforge.dart
import 'package:flutter/foundation.dart';
import 'package:insforge/insforge.dart';

import 'secure_session_storage.dart';

/// supabase_flutter-style global accessor for a single [InsforgeClient].
///
/// Call [initialize] once near app startup (it awaits session restoration),
/// then read [instance] anywhere. Apps that prefer dependency injection can
/// construct an [InsforgeClient] directly instead.
class Insforge {
  Insforge._();

  static InsforgeClient? _client;

  /// The initialized client.
  ///
  /// Throws a [StateError] if [initialize] has not completed.
  static InsforgeClient get instance {
    final client = _client;
    if (client == null) {
      throw StateError(
        'Insforge.instance was read before Insforge.initialize() completed. '
        'Call `await Insforge.initialize(url: ..., anonKey: ...)` in main().',
      );
    }
    return client;
  }

  /// Whether [initialize] has completed.
  static bool get isInitialized => _client != null;

  /// Builds the global client and restores any persisted session.
  ///
  /// [openRouterApiKey] enables `Insforge.instance.ai`. Tests may pass
  /// [sessionStorageForTest] to avoid the platform secure store.
  static Future<void> initialize({
    required String url,
    required String anonKey,
    String? apiKey,
    String? openRouterApiKey,
    InsforgeOptions? options,
    @visibleForTesting SessionStorage? sessionStorageForTest,
  }) async {
    final client = InsforgeClient(
      url,
      anonKey,
      apiKey: apiKey,
      openRouterApiKey: openRouterApiKey,
      options: options,
      sessionStorage: sessionStorageForTest ?? SecureSessionStorage(),
    );
    await client.restoreSession();
    _client = client;
  }

  /// Disposes and clears the global client. Visible for testing.
  @visibleForTesting
  static void resetForTest() {
    _client?.dispose();
    _client = null;
  }
}
