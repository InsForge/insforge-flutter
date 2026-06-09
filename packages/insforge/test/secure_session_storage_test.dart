// packages/insforge/test/secure_session_storage_test.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insforge/insforge.dart';

/// In-memory fake of the secure-storage platform channel, so the test runs on
/// the Dart VM without a real device keystore.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> store = <String, String>{};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      store.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    store.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      store[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map<String, String>.from(store);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    store[key] = value;
  }
}

void main() {
  late _FakeSecureStoragePlatform platform;
  late SecureSessionStorage storage;

  setUp(() {
    platform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    storage = SecureSessionStorage(
      secureStorage: const FlutterSecureStorage(),
    );
  });

  test('is a SessionStorage', () {
    expect(storage, isA<SessionStorage>());
  });

  test('write/read/delete delegate to flutter_secure_storage', () async {
    expect(await storage.read('insforge_access_token'), isNull);

    await storage.write('insforge_access_token', 'jwt-abc');
    expect(platform.store['insforge_access_token'], 'jwt-abc');
    expect(await storage.read('insforge_access_token'), 'jwt-abc');

    await storage.delete('insforge_access_token');
    expect(platform.store.containsKey('insforge_access_token'), isFalse);
    expect(await storage.read('insforge_access_token'), isNull);
  });
}
