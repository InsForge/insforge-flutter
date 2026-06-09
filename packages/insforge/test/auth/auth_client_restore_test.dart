// packages/insforge_auth/test/auth_client_restore_test.dart
import 'dart:convert';

import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge/insforge.dart';
import 'package:test/test.dart';

/// Builds an unsigned JWT whose `exp` is [delta] in the future.
String _jwtExpiringIn(Duration delta) {
  final exp =
      (DateTime.now().toUtc().add(delta).millisecondsSinceEpoch / 1000).floor();
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'});
  final body = seg(<String, dynamic>{'sub': 'u-1', 'exp': exp});
  return '$header.$body.sig';
}

void main() {
  late InsforgeHttpClient http;
  late DioAdapter adapter;
  late InMemorySessionStorage storage;
  late AuthClient auth;

  setUp(() {
    http = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    adapter = DioAdapter(dio: http.dio);
    storage = InMemorySessionStorage();
    auth = AuthClient(http, storage);
  });

  test('returns null when nothing is stored', () async {
    final restored = await auth.restoreSession();
    expect(restored, isNull);
    expect(auth.currentSession, isNull);
  });

  test('restores a stored session with a fresh (far-future) token', () async {
    final token = _jwtExpiringIn(const Duration(hours: 1));
    await storage.write('insforge_access_token', token);
    await storage.write('insforge_refresh_token', 'stored-refresh');
    await storage.write(
      'insforge_user',
      jsonEncode(<String, dynamic>{'id': 'u-1', 'email': 'a@b.com'}),
    );

    final restored = await auth.restoreSession();

    expect(restored, isNotNull);
    expect(restored!.accessToken, token);
    expect(auth.currentUser?.id, 'u-1');
    expect(http.accessToken, token);
  });

  test('proactively refreshes when the stored token expires within leeway',
      () async {
    final nearlyExpired = _jwtExpiringIn(const Duration(seconds: 5));
    await storage.write('insforge_access_token', nearlyExpired);
    await storage.write('insforge_refresh_token', 'stored-refresh');
    await storage.write(
      'insforge_user',
      jsonEncode(<String, dynamic>{'id': 'u-1', 'email': 'a@b.com'}),
    );

    adapter.onPost(
      '/api/auth/refresh',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{'id': 'u-1', 'email': 'a@b.com'},
        'accessToken': 'refreshed-access',
        'refreshToken': 'refreshed-refresh',
      }),
      data: <String, dynamic>{'refreshToken': 'stored-refresh'},
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );

    final restored = await auth.restoreSession();

    expect(restored?.accessToken, 'refreshed-access');
    expect(http.accessToken, 'refreshed-access');
    expect(await storage.read('insforge_access_token'), 'refreshed-access');
  });
}
