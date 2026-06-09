// packages/insforge/lib/src/secure_session_storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:insforge_core/insforge_core.dart';

/// A [SessionStorage] backed by `flutter_secure_storage` (Keychain on iOS,
/// EncryptedSharedPreferences/Keystore on Android).
///
/// This is the default session store used by [InsforgeClient] when no custom
/// storage is supplied. Inject a [FlutterSecureStorage] to customize platform
/// options or to substitute a fake in tests.
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? secureStorage})
      : _storage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
