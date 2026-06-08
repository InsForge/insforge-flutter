// packages/insforge_auth/test/auth_client_profile_test.dart
import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_auth/insforge_auth.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

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

  test('getProfile fetches a user profile by id', () async {
    adapter.onGet(
      '/api/auth/profiles/u-42',
      (server) => server.reply(200, <String, dynamic>{
        'id': 'u-42',
        'profile': <String, dynamic>{'name': 'Grace', 'avatar_url': 'g.png'},
      }),
    );

    final profile = await auth.getProfile('u-42');
    expect(profile.id, 'u-42');
    expect(profile.profile['name'], 'Grace');
  });

  test('updateProfile patches the current profile and emits userUpdated',
      () async {
    // Sign in first so there is a current session to update.
    adapter.onPost(
      '/api/auth/sessions',
      (server) => server.reply(200, <String, dynamic>{
        'user': <String, dynamic>{
          'id': 'u-1',
          'email': 'a@b.com',
          'profile': <String, dynamic>{'name': 'Old'},
        },
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
      }),
      data: Matchers.any,
      queryParameters: <String, dynamic>{'client_type': 'mobile'},
    );
    adapter.onPatch(
      '/api/auth/profiles/current',
      (server) => server.reply(200, <String, dynamic>{
        'id': 'u-1',
        'profile': <String, dynamic>{'name': 'New', 'avatar_url': 'n.png'},
      }),
      data: <String, dynamic>{
        'profile': <String, dynamic>{'name': 'New', 'avatar_url': 'n.png'},
      },
    );

    await auth.signIn(email: 'a@b.com', password: 'pw');

    final states = <AuthState>[];
    final sub = auth.onAuthStateChange.listen(states.add);

    final updated = await auth.updateProfile(<String, dynamic>{
      'name': 'New',
      'avatar_url': 'n.png',
    });

    expect(updated.profile['name'], 'New');
    // In-memory user reflects the new profile.
    expect(auth.currentUser?.name, 'New');
    expect(auth.currentUser?.avatarUrl, 'n.png');

    await Future<void>.delayed(Duration.zero);
    expect(states.single.event, AuthChangeEvent.userUpdated);
    await sub.cancel();
  });
}
