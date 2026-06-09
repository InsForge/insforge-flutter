// packages/insforge_core/lib/src/session_storage.dart

/// Persists small auth-session values (tokens, serialized user).
///
/// Implementations must be safe to call from async code. The umbrella
/// `insforge` package ships a `flutter_secure_storage`-backed implementation;
/// this package provides only the interface and an in-memory variant.
abstract class SessionStorage {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// Non-persistent [SessionStorage] backed by an in-process map.
class InMemorySessionStorage implements SessionStorage {
  final Map<String, String> _store = <String, String>{};

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> delete(String key) async => _store.remove(key);
}
