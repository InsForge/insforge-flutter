# InsForge Flutter SDK — Plan 5: `insforge_functions` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart `insforge_functions` package: a thin `FunctionsClient` that invokes InsForge edge functions over the `${baseUrl}/functions/{slug}` execution path (note: **no** `/api` prefix), supporting all HTTP verbs, JSON bodies, query parameters, custom headers, and a typed convenience wrapper. It reuses `InsforgeHttpClient` from `insforge_core` for transport, auth-header injection, and error mapping.

**Architecture:** `FunctionsClient` wraps the shared `InsforgeHttpClient`. `invoke` constructs the path `'/functions/$slug'` (relative to the client's `baseUrl`) and delegates to `http.request`. For POST/PUT/PATCH the caller's `body` is sent as the JSON request body; for GET/DELETE the `queryParameters` are sent instead. The decoded response (`response.data` — a JSON map/list, or a raw string/bytes) is returned directly. Non-2xx responses are already mapped to `InsforgeHttpException` by `InsforgeHttpClient.request`, so a 404 (function not found / not active) and a 502 (Deno runtime) surface as typed exceptions carrying the server's `{error, details?}` envelope (tolerated by `ErrorResponse.fromJson`). The function enforces its own auth; the SDK adds no extra auth requirement beyond the core client's default header injection.

**Tech Stack:** Dart ≥ 3.5 (pub workspaces), `dio` ^5.7.0, `meta` ^1.15.0, `insforge_core` (path dep), `test`, `http_mock_adapter`, `lints`.

**Prerequisite:** The Flutter SDK (which bundles Dart) must be installed and on `PATH` (`dart --version` must work). Plan 1 (`insforge_core`) must be complete — this package imports `package:insforge_core/insforge_core.dart`.

**Plan series:** This is plan 5 of 7. Preceding: 01 core, 02 auth, 03 database, 04 storage. Following: 06 ai, 07 umbrella + sample. This plan appends `packages/insforge_functions` to the workspace member list created in Plan 1.

---

## File Structure

```
insforge-flutter/
├── pubspec.yaml                              # workspace root (MODIFY: add member)
└── packages/
    └── insforge_functions/
        ├── pubspec.yaml
        ├── analysis_options.yaml             # includes root lints
        ├── lib/
        │   ├── insforge_functions.dart       # public exports
        │   └── src/
        │       └── functions_client.dart     # FunctionsClient
        └── test/
            ├── functions_invoke_test.dart    # path/method/body pass-through
            └── functions_error_test.dart     # 404 → InsforgeHttpException; invokeAs
```

---

## Task 1: Package scaffolding

**Files:**
- Create: `packages/insforge_functions/pubspec.yaml`
- Create: `packages/insforge_functions/analysis_options.yaml`
- Create: `packages/insforge_functions/lib/insforge_functions.dart`
- Modify: `pubspec.yaml` (workspace root)

- [ ] **Step 1: Create the package `pubspec.yaml`**

```yaml
# packages/insforge_functions/pubspec.yaml
name: insforge_functions
description: Edge function invocation for the InsForge Flutter SDK.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.5.0

dependencies:
  dio: ^5.7.0
  meta: ^1.15.0
  insforge_core:
    path: ../insforge_core

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
  http_mock_adapter: ^0.6.1
```

- [ ] **Step 2: Create the package-local `analysis_options.yaml`**

```yaml
# packages/insforge_functions/analysis_options.yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 3: Create a placeholder library export file**

```dart
// packages/insforge_functions/lib/insforge_functions.dart
/// Edge function invocation for the InsForge Flutter SDK.
library insforge_functions;

// Exports are added as each component lands in later tasks.
```

- [ ] **Step 4: Register the package in the workspace root `pubspec.yaml`**

In the repo-root `pubspec.yaml` (created in Plan 1), append `- packages/insforge_functions` to the `workspace:` list so it reads:

```yaml
# pubspec.yaml (workspace root) — workspace section after this change
workspace:
  - packages/insforge_core
  - packages/insforge_auth
  - packages/insforge_database
  - packages/insforge_storage
  - packages/insforge_functions
```

(Only add the `- packages/insforge_functions` line; leave any other members already present untouched. If an earlier plan has not yet added one of the lines above, just ensure `insforge_core` and `insforge_functions` are both present.)

- [ ] **Step 5: Resolve dependencies**

Run: `dart pub get` (from repo root)
Expected: resolves the workspace including `insforge_functions`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/insforge_functions/pubspec.yaml packages/insforge_functions/analysis_options.yaml packages/insforge_functions/lib/insforge_functions.dart
git commit -m "feat(functions): add insforge_functions package skeleton"
```

---

## Task 2: `FunctionsClient.invoke` — path / method / body pass-through

**Files:**
- Create: `packages/insforge_functions/lib/src/functions_client.dart`
- Test: `packages/insforge_functions/test/functions_invoke_test.dart`
- Modify: `packages/insforge_functions/lib/insforge_functions.dart`

The test uses a tiny custom `HttpClientAdapter` that records each request's resolved path, method, body, query parameters, and headers, and returns a canned JSON 200 — this lets us assert exactly what `FunctionsClient` sends to the transport without coupling to a mock-adapter version.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_functions/test/functions_invoke_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:insforge_functions/insforge_functions.dart';
import 'package:test/test.dart';

/// Records each request and returns a fixed JSON 200.
class RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<String> bodies = <String>[];
  String responseJson;

  RecordingAdapter([this.responseJson = '{"message":"Hello, World!"}']);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      final bytes = chunks.expand((Uint8List c) => c).toList();
      bodies.add(utf8.decode(bytes));
    } else {
      bodies.add('');
    }
    return ResponseBody.fromString(
      responseJson,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

InsforgeHttpClient _client(RecordingAdapter adapter) {
  final client = InsforgeHttpClient(
    baseUrl: 'https://x.insforge.app',
    anonKey: 'anon-123',
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  group('FunctionsClient.invoke', () {
    test('POSTs to /functions/{slug} with a JSON body and returns decoded data',
        () async {
      final adapter = RecordingAdapter('{"message":"Hello, John!"}');
      final functions = FunctionsClient(_client(adapter));

      final result = await functions.invoke(
        'hello-world',
        body: <String, dynamic>{'name': 'John'},
      );

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/functions/hello-world');
      expect(jsonDecode(adapter.bodies.single), <String, dynamic>{'name': 'John'});
      expect(result, <String, dynamic>{'message': 'Hello, John!'});
    });

    test('GET override routes correctly and sends query params, not a body',
        () async {
      final adapter = RecordingAdapter();
      final functions = FunctionsClient(_client(adapter));

      await functions.invoke(
        'search',
        method: 'GET',
        queryParameters: <String, dynamic>{'q': 'flutter'},
      );

      final req = adapter.requests.single;
      expect(req.method, 'GET');
      expect(req.uri.path, '/functions/search');
      expect(req.uri.queryParameters['q'], 'flutter');
      expect(adapter.bodies.single, isEmpty);
    });

    test('forwards custom headers', () async {
      final adapter = RecordingAdapter();
      final functions = FunctionsClient(_client(adapter));

      await functions.invoke(
        'webhook',
        body: <String, dynamic>{'ok': true},
        headers: <String, String>{'X-Custom': 'value-42'},
      );

      expect(adapter.requests.single.headers['X-Custom'], 'value-42');
    });

    test('returns a decoded list when the function responds with a JSON array',
        () async {
      final adapter = RecordingAdapter('[1,2,3]');
      final functions = FunctionsClient(_client(adapter));

      final result = await functions.invoke('numbers');

      expect(result, <int>[1, 2, 3]);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_functions && dart test test/functions_invoke_test.dart`
Expected: FAIL — `FunctionsClient` is not defined.

- [ ] **Step 3: Write `functions_client.dart`**

```dart
// packages/insforge_functions/lib/src/functions_client.dart
import 'package:insforge_core/insforge_core.dart';

/// Client for invoking InsForge edge functions (Deno runtime).
///
/// Functions are executed via the `${baseUrl}/functions/{slug}` path — note
/// there is **no** `/api` prefix, unlike the other modules. The SDK enforces no
/// additional auth; each function enforces its own. The shared
/// [InsforgeHttpClient] still injects the default `Authorization`/`x-api-key`
/// headers, which a function may choose to read.
class FunctionsClient {
  FunctionsClient(this._http);

  final InsforgeHttpClient _http;

  /// Invokes the edge function identified by [slug].
  ///
  /// * [method] — HTTP verb (default `POST`). For body-bearing verbs
  ///   (`POST`/`PUT`/`PATCH`) the [body] is sent as the JSON request body; for
  ///   `GET`/`DELETE` the [body] is ignored and [queryParameters] are sent.
  /// * [body] — JSON-serializable request payload.
  /// * [headers] — extra headers merged onto the request.
  /// * [queryParameters] — URL query parameters.
  ///
  /// Returns the decoded response: a `Map<String, dynamic>` or `List` for JSON
  /// bodies, or a raw `String`/bytes for non-JSON responses. A non-2xx response
  /// throws an [InsforgeHttpException] (e.g. 404 function not found / not
  /// active; 502 Deno runtime failure).
  Future<dynamic> invoke(
    String slug, {
    String method = 'POST',
    Object? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final sendsBody = _methodSendsBody(method);
    final response = await _http.request<dynamic>(
      method,
      '/functions/$slug',
      data: sendsBody ? body : null,
      queryParameters: queryParameters,
      headers: headers,
    );
    return response.data;
  }

  /// Typed convenience over [invoke]: invokes [slug] and maps the JSON object
  /// response through [fromJson].
  ///
  /// Throws an [InsforgeSerializationException] if the response is not a JSON
  /// object.
  Future<T> invokeAs<T>(
    String slug,
    T Function(Map<String, dynamic> json) fromJson, {
    String method = 'POST',
    Object? body,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
  }) async {
    final data = await invoke(
      slug,
      method: method,
      body: body,
      headers: headers,
      queryParameters: queryParameters,
    );
    if (data is Map<String, dynamic>) {
      return fromJson(data);
    }
    throw InsforgeSerializationException(
      'Expected a JSON object from function "$slug" but got '
      '${data.runtimeType}.',
    );
  }

  bool _methodSendsBody(String method) {
    final m = method.toUpperCase();
    return m == 'POST' || m == 'PUT' || m == 'PATCH';
  }
}
```

- [ ] **Step 4: Export it**

Replace the trailing comment in `packages/insforge_functions/lib/insforge_functions.dart` with:

```dart
export 'src/functions_client.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_functions && dart test test/functions_invoke_test.dart`
Expected: PASS (all four tests).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_functions/lib/src/functions_client.dart packages/insforge_functions/lib/insforge_functions.dart packages/insforge_functions/test/functions_invoke_test.dart
git commit -m "feat(functions): add FunctionsClient.invoke with method/body pass-through"
```

---

## Task 3: Error mapping + `invokeAs`

**Files:**
- Test: `packages/insforge_functions/test/functions_error_test.dart`

The implementation already exists (`invoke` delegates to `InsforgeHttpClient.request`, which maps non-2xx to `InsforgeHttpException`; `invokeAs` is in Task 2). This task uses `http_mock_adapter`'s `DioAdapter` for response-shape tests and locks in the error/typed-mapping behavior.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_functions/test/functions_error_test.dart
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:insforge_functions/insforge_functions.dart';
import 'package:test/test.dart';

/// Tiny typed model used to exercise invokeAs.
class Greeting {
  Greeting(this.message);
  final String message;

  factory Greeting.fromJson(Map<String, dynamic> json) =>
      Greeting(json['message'] as String);
}

InsforgeHttpClient _clientWith(DioAdapter adapter) {
  final client = InsforgeHttpClient(
    baseUrl: 'https://x.insforge.app',
    anonKey: 'anon-123',
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  group('FunctionsClient errors', () {
    test('a 404 throws InsforgeHttpException with statusCode 404', () async {
      final dioAdapter = DioAdapter(dio: Dio());
      final client = _clientWith(dioAdapter);
      dioAdapter.onPost(
        '/functions/missing',
        (server) => server.reply(
          404,
          <String, dynamic>{'error': 'Function not found or not active'},
        ),
        data: <String, dynamic>{'x': 1},
      );

      final functions = FunctionsClient(client);

      await expectLater(
        () => functions.invoke('missing', body: <String, dynamic>{'x': 1}),
        throwsA(
          isA<InsforgeHttpException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.error, 'error', 'Function not found or not active'),
        ),
      );
    });

    test('a 502 throws InsforgeHttpException with statusCode 502', () async {
      final dioAdapter = DioAdapter(dio: Dio());
      final client = _clientWith(dioAdapter);
      dioAdapter.onPost(
        '/functions/broken',
        (server) => server.reply(
          502,
          <String, dynamic>{'error': 'Failed to connect to Deno runtime'},
        ),
        data: null,
      );

      final functions = FunctionsClient(client);

      await expectLater(
        () => functions.invoke('broken'),
        throwsA(isA<InsforgeHttpException>()
            .having((e) => e.statusCode, 'statusCode', 502)),
      );
    });
  });

  group('FunctionsClient.invokeAs', () {
    test('maps a JSON object response via fromJson', () async {
      final dioAdapter = DioAdapter(dio: Dio());
      final client = _clientWith(dioAdapter);
      dioAdapter.onPost(
        '/functions/hello-world',
        (server) => server.reply(
          200,
          <String, dynamic>{'message': 'Hello, Ada!'},
        ),
        data: <String, dynamic>{'name': 'Ada'},
      );

      final functions = FunctionsClient(client);

      final greeting = await functions.invokeAs<Greeting>(
        'hello-world',
        Greeting.fromJson,
        body: <String, dynamic>{'name': 'Ada'},
      );

      expect(greeting.message, 'Hello, Ada!');
    });

    test('throws InsforgeSerializationException for a non-object response',
        () async {
      final dioAdapter = DioAdapter(dio: Dio());
      final client = _clientWith(dioAdapter);
      dioAdapter.onPost(
        '/functions/numbers',
        (server) => server.reply(200, <int>[1, 2, 3]),
        data: null,
      );

      final functions = FunctionsClient(client);

      await expectLater(
        () => functions.invokeAs<Greeting>('numbers', Greeting.fromJson),
        throwsA(isA<InsforgeSerializationException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `cd packages/insforge_functions && dart test test/functions_error_test.dart`
Expected: PASS (all four tests — implementation from Task 2 + core error mapping already handle these).

- [ ] **Step 3: Run the full package suite + analyze**

Run: `cd packages/insforge_functions && dart test && dart analyze`
Expected: all tests PASS; "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add packages/insforge_functions/test/functions_error_test.dart
git commit -m "test(functions): cover 404/502 mapping and invokeAs typed wrapper"
```

---

## Self-Review Notes

- **Spec coverage (design §4.5):** `FunctionsClient(http)` with `invoke(slug, {method='POST', body, headers, queryParameters}) → dynamic` (Task 2), execution path `${baseUrl}/functions/{slug}` with **no** `/api` prefix (Task 2, asserted by `req.uri.path == '/functions/hello-world'`), all HTTP verbs via the `method` param (default POST), body for POST/PUT/PATCH vs query params for GET/DELETE (`_methodSendsBody`, Task 2), custom-header forwarding (Task 2), decoded JSON map/list or raw return (`response.data`, Task 2), and error mapping for 404 (not found / not active) and 502 (Deno runtime) inherited from `InsforgeHttpClient.request` → `InsforgeHttpException` (Task 3). The `{error, details?}` functions envelope is tolerated by `ErrorResponse.fromJson` (built in Plan 1). The optional typed convenience `invokeAs<T>` is included (Tasks 2-3). Covered.
- **Design deviation — `functionsBaseUrl` not implemented:** Design §4.5 lists an optional `{functionsBaseUrl}` constructor parameter (the JS SDK derives a `*.functions.insforge.app` subhosting host and falls back to the proxy path on 404). This plan deliberately ships only the proxy path (`/functions/{slug}` relative to the client `baseUrl`), because `InsforgeHttpClient.request` takes a path relative to a single configured `baseUrl` and the spec's testing strategy (design §6) only requires "path construction, method/body pass-through." Subhosting-host derivation + 404-fallback can be added later as an opt-in once core supports per-request absolute URLs; flagged here so a later plan can extend without breaking the `invoke` signature.
- **Type consistency:** `FunctionsClient(InsforgeHttpClient http)`, `invoke(...)`, and `invokeAs<T>(slug, fromJson, {...})` are the names the umbrella package (Plan 7) wires up via a lazy `functions` getter — keep them stable. Imported from core: `InsforgeHttpClient.request`, `InsforgeHttpException`, `InsforgeSerializationException`.
- **Testing approach:** request-shape assertions (path/method/body/query/headers) use a hand-rolled `RecordingAdapter` to avoid coupling to a mock-adapter version; response-shape/error tests use `http_mock_adapter`'s `DioAdapter` per the prescribed recipe. `_http` field is referenced only through `request`, so refactors to core transport remain isolated.
