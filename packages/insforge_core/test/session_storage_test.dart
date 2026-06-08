// packages/insforge_core/test/session_storage_test.dart
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  group('InMemorySessionStorage', () {
    test('writes, reads, and deletes values', () async {
      final SessionStorage storage = InMemorySessionStorage();

      expect(await storage.read('token'), isNull);

      await storage.write('token', 'abc');
      expect(await storage.read('token'), 'abc');

      await storage.write('token', 'def');
      expect(await storage.read('token'), 'def');

      await storage.delete('token');
      expect(await storage.read('token'), isNull);
    });
  });
}
