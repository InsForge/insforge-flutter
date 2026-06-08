# InsForge Flutter SDK — Plan 1: Workspace + `insforge_core` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the monorepo (Dart pub workspace + melos) and build the pure-Dart `insforge_core` package: the shared HTTP client (dio) with auth-token injection and single-flight 401 refresh, the error model, the session-storage interface, options, and small utilities.

**Architecture:** A pub workspace holds all SDK packages. `insforge_core` is the kernel every feature package depends on. Its `InsforgeHttpClient` wraps a single `dio.Dio`, injects auth headers per request, transparently refreshes the access token once on 401 (deduped across concurrent failures), and maps transport errors to a typed exception hierarchy. No Flutter dependency.

**Tech Stack:** Dart ≥ 3.5 (pub workspaces), `dio` ^5.7.0, `test`, `lints`, `melos` (dev tooling).

**Prerequisite:** The Flutter SDK (which bundles Dart) must be installed and on `PATH` (`dart --version` must work). It is not currently installed on this machine — install it before executing.

**Plan series:** This is plan 1 of 7. Subsequent plans: 02 auth, 03 database, 04 storage, 05 functions, 06 ai, 07 umbrella + sample. Each later package adds itself to the workspace member list created here.

---

## File Structure

```
insforge-flutter/
├── pubspec.yaml                         # pub workspace root
├── melos.yaml                           # task runner
├── analysis_options.yaml                # shared lints
├── .github/workflows/ci.yaml            # analyze + test
└── packages/
    └── insforge_core/
        ├── pubspec.yaml
        ├── analysis_options.yaml        # includes root lints
        ├── lib/
        │   ├── insforge_core.dart       # public exports
        │   └── src/
        │       ├── errors.dart          # exception hierarchy
        │       ├── error_response.dart  # server error envelope parsing
        │       ├── session_storage.dart # SessionStorage + InMemorySessionStorage
        │       ├── options.dart         # InsforgeOptions, LogLevel
        │       ├── url.dart             # normalizeBaseUrl
        │       ├── dates.dart           # parseInsforgeDate
        │       ├── logging_interceptor.dart
        │       └── http_client.dart     # InsforgeHttpClient
        └── test/
            ├── error_response_test.dart
            ├── session_storage_test.dart
            ├── url_test.dart
            ├── dates_test.dart
            ├── logging_interceptor_test.dart
            ├── http_client_auth_test.dart
            ├── http_client_error_test.dart
            └── http_client_refresh_test.dart
```

---

## Task 1: Workspace scaffolding

**Files:**
- Create: `pubspec.yaml`
- Create: `melos.yaml`
- Create: `analysis_options.yaml`
- Create: `.gitignore`

- [ ] **Step 1: Create the workspace root `pubspec.yaml`**

```yaml
# pubspec.yaml
name: _insforge_workspace
publish_to: none
environment:
  sdk: ^3.5.0

# Pub workspace members. Later plans append their package paths here.
workspace:
  - packages/insforge_core

dev_dependencies:
  melos: ^6.1.0
```

- [ ] **Step 2: Create `melos.yaml`**

```yaml
# melos.yaml
name: insforge_flutter

packages:
  - packages/**
  - samples/**

scripts:
  analyze:
    description: Analyze all packages.
    run: dart analyze .
  test:
    description: Run tests in every package that has a test/ dir.
    run: dart test
    exec:
      concurrency: 1
    packageFilters:
      dirExists: test
```

- [ ] **Step 3: Create shared `analysis_options.yaml`**

```yaml
# analysis_options.yaml
include: package:lints/recommended.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true

linter:
  rules:
    - prefer_final_locals
    - prefer_single_quotes
    - avoid_print
    - require_trailing_commas
```

- [ ] **Step 4: Create `.gitignore`**

```gitignore
# Dart/Flutter
.dart_tool/
.packages
build/
pubspec.lock
**/.flutter-plugins
**/.flutter-plugins-dependencies
.fvm/

# IDE
.idea/
*.iml
.vscode/

# OS
.DS_Store
```

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml melos.yaml analysis_options.yaml .gitignore
git commit -m "chore: scaffold pub workspace + melos"
```

---

## Task 2: `insforge_core` package skeleton

**Files:**
- Create: `packages/insforge_core/pubspec.yaml`
- Create: `packages/insforge_core/analysis_options.yaml`
- Create: `packages/insforge_core/lib/insforge_core.dart`

- [ ] **Step 1: Create the package `pubspec.yaml`**

```yaml
# packages/insforge_core/pubspec.yaml
name: insforge_core
description: Core HTTP, auth-token, error, and storage primitives shared by the InsForge Flutter SDK modules.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ^3.5.0

dependencies:
  dio: ^5.7.0
  meta: ^1.15.0

dev_dependencies:
  lints: ^4.0.0
  test: ^1.25.0
```

- [ ] **Step 2: Create the package-local `analysis_options.yaml`**

```yaml
# packages/insforge_core/analysis_options.yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 3: Create a placeholder library export file**

```dart
// packages/insforge_core/lib/insforge_core.dart
/// Core primitives for the InsForge Flutter SDK.
library insforge_core;

// Exports are added as each component lands in later tasks.
```

- [ ] **Step 4: Resolve dependencies**

Run: `dart pub get` (from repo root)
Expected: resolves the workspace including `insforge_core`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add packages/insforge_core/pubspec.yaml packages/insforge_core/analysis_options.yaml packages/insforge_core/lib/insforge_core.dart
git commit -m "feat(core): add insforge_core package skeleton"
```

---

## Task 3: Exception hierarchy

**Files:**
- Create: `packages/insforge_core/lib/src/errors.dart`
- Modify: `packages/insforge_core/lib/insforge_core.dart`

There is no behavior to unit-test in the exceptions beyond construction and `toString`; the `error_response` test in Task 4 exercises them indirectly. Keep this task minimal.

- [ ] **Step 1: Write `errors.dart`**

```dart
// packages/insforge_core/lib/src/errors.dart

/// Base class for all errors thrown by the InsForge SDK.
class InsforgeException implements Exception {
  InsforgeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'InsforgeException: $message';
}

/// Thrown when the backend returns a non-2xx HTTP response.
class InsforgeHttpException extends InsforgeException {
  InsforgeHttpException({
    required this.statusCode,
    required String message,
    this.error,
    this.nextActions,
    Object? cause,
  }) : super(message, cause: cause);

  /// HTTP status code (e.g. 401, 404).
  final int statusCode;

  /// Server error code/string (e.g. `AUTH_INVALID_CREDENTIALS`).
  final String? error;

  /// Server-suggested remediation, when provided.
  final String? nextActions;

  @override
  String toString() {
    final actions = nextActions != null ? ' | nextActions: $nextActions' : '';
    return 'InsforgeHttpException($statusCode, error: $error): $message$actions';
  }
}

/// Thrown for authentication-specific failures.
class InsforgeAuthException extends InsforgeException {
  InsforgeAuthException(super.message, {super.cause});
}

/// Thrown for transport-level failures (timeouts, no connection).
class InsforgeNetworkException extends InsforgeException {
  InsforgeNetworkException(super.message, {super.cause});
}

/// Thrown when a response body cannot be parsed into the expected shape.
class InsforgeSerializationException extends InsforgeException {
  InsforgeSerializationException(super.message, {super.cause});
}
```

- [ ] **Step 2: Export it**

In `packages/insforge_core/lib/insforge_core.dart`, replace the trailing comment with:

```dart
export 'src/errors.dart';
```

- [ ] **Step 3: Analyze**

Run: `cd packages/insforge_core && dart analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add packages/insforge_core/lib/src/errors.dart packages/insforge_core/lib/insforge_core.dart
git commit -m "feat(core): add exception hierarchy"
```

---

## Task 4: Server error envelope parsing (`ErrorResponse`)

**Files:**
- Create: `packages/insforge_core/lib/src/error_response.dart`
- Test: `packages/insforge_core/test/error_response_test.dart`
- Modify: `packages/insforge_core/lib/insforge_core.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_core/test/error_response_test.dart
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  group('ErrorResponse.fromJson', () {
    test('parses the auth/records envelope', () {
      final r = ErrorResponse.fromJson(<String, dynamic>{
        'error': 'AUTH_INVALID_CREDENTIALS',
        'message': 'Invalid email or password',
        'statusCode': 401,
        'nextActions': 'Check the credentials and retry.',
      });
      expect(r.error, 'AUTH_INVALID_CREDENTIALS');
      expect(r.message, 'Invalid email or password');
      expect(r.statusCode, 401);
      expect(r.nextActions, 'Check the credentials and retry.');
    });

    test('parses the functions/ai envelope (details + code, no message)', () {
      final r = ErrorResponse.fromJson(<String, dynamic>{
        'error': 'BadRequest',
        'details': 'model is required',
        'code': 'invalid_request',
      });
      // error code prefers `error`, falling back to `code`.
      expect(r.error, 'BadRequest');
      // message falls back to details when message is absent.
      expect(r.message, 'model is required');
      expect(r.statusCode, isNull);
      expect(r.nextActions, isNull);
    });

    test('falls back to a generic message when nothing usable is present', () {
      final r = ErrorResponse.fromJson(<String, dynamic>{});
      expect(r.message, 'Unknown error');
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_core && dart test test/error_response_test.dart`
Expected: FAIL — `ErrorResponse` is not defined.

- [ ] **Step 3: Write `error_response.dart`**

```dart
// packages/insforge_core/lib/src/error_response.dart

/// Parsed representation of an InsForge error response body.
///
/// Tolerant of two server envelope shapes:
/// * auth/records/tables/storage: `{error, message, statusCode, nextActions?}`
/// * functions/ai: `{error, details?, code?}`
class ErrorResponse {
  ErrorResponse({
    this.error,
    required this.message,
    this.statusCode,
    this.nextActions,
  });

  final String? error;
  final String message;
  final int? statusCode;
  final String? nextActions;

  factory ErrorResponse.fromJson(Map<String, dynamic> json) {
    final message =
        (json['message'] ?? json['details'] ?? json['error'] ?? 'Unknown error')
            .toString();
    final code = json['error'] ?? json['code'];
    final rawStatus = json['statusCode'];
    return ErrorResponse(
      error: code?.toString(),
      message: message,
      statusCode: rawStatus is int ? rawStatus : null,
      nextActions: json['nextActions']?.toString(),
    );
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_core/lib/insforge_core.dart`:

```dart
export 'src/error_response.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_core && dart test test/error_response_test.dart`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_core/lib/src/error_response.dart packages/insforge_core/lib/insforge_core.dart packages/insforge_core/test/error_response_test.dart
git commit -m "feat(core): add tolerant ErrorResponse parsing"
```

---

## Task 5: Session storage interface

**Files:**
- Create: `packages/insforge_core/lib/src/session_storage.dart`
- Test: `packages/insforge_core/test/session_storage_test.dart`
- Modify: `packages/insforge_core/lib/insforge_core.dart`

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_core && dart test test/session_storage_test.dart`
Expected: FAIL — `SessionStorage`/`InMemorySessionStorage` not defined.

- [ ] **Step 3: Write `session_storage.dart`**

```dart
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
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_core/lib/insforge_core.dart`:

```dart
export 'src/session_storage.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_core && dart test test/session_storage_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_core/lib/src/session_storage.dart packages/insforge_core/lib/insforge_core.dart packages/insforge_core/test/session_storage_test.dart
git commit -m "feat(core): add SessionStorage interface + in-memory impl"
```

---

## Task 6: Options + log level

**Files:**
- Create: `packages/insforge_core/lib/src/options.dart`
- Modify: `packages/insforge_core/lib/insforge_core.dart`

This is a plain value type; it is exercised by the HTTP client tests in Tasks 9-11. No dedicated test needed.

- [ ] **Step 1: Write `options.dart`**

```dart
// packages/insforge_core/lib/src/options.dart

/// Verbosity of SDK request/response logging.
enum LogLevel { none, error, info, debug, verbose }

/// Tunable client behavior shared across modules.
class InsforgeOptions {
  const InsforgeOptions({
    this.logLevel = LogLevel.none,
    this.customHeaders = const <String, String>{},
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 60),
  });

  final LogLevel logLevel;
  final Map<String, String> customHeaders;
  final Duration connectTimeout;
  final Duration receiveTimeout;
}
```

- [ ] **Step 2: Export it**

Append to `packages/insforge_core/lib/insforge_core.dart`:

```dart
export 'src/options.dart';
```

- [ ] **Step 3: Analyze**

Run: `cd packages/insforge_core && dart analyze`
Expected: "No issues found!"

- [ ] **Step 4: Commit**

```bash
git add packages/insforge_core/lib/src/options.dart packages/insforge_core/lib/insforge_core.dart
git commit -m "feat(core): add InsforgeOptions and LogLevel"
```

---

## Task 7: Base-URL normalization

**Files:**
- Create: `packages/insforge_core/lib/src/url.dart`
- Test: `packages/insforge_core/test/url_test.dart`
- Modify: `packages/insforge_core/lib/insforge_core.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_core/test/url_test.dart
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('adds https scheme when missing and trims trailing slash', () {
      expect(normalizeBaseUrl('api.example.com/'), 'https://api.example.com');
    });

    test('keeps an explicit http scheme', () {
      expect(normalizeBaseUrl('http://localhost:7130'), 'http://localhost:7130');
    });

    test('uses http when useHttps is false and no scheme given', () {
      expect(
        normalizeBaseUrl('localhost:7130', useHttps: false),
        'http://localhost:7130',
      );
    });

    test('rejects URLs that already contain a module path', () {
      expect(
        () => normalizeBaseUrl('https://x.com/api/auth'),
        throwsA(isA<InsforgeException>()),
      );
    });

    test('rejects an empty URL', () {
      expect(() => normalizeBaseUrl('   '), throwsA(isA<InsforgeException>()));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_core && dart test test/url_test.dart`
Expected: FAIL — `normalizeBaseUrl` not defined.

- [ ] **Step 3: Write `url.dart`**

```dart
// packages/insforge_core/lib/src/url.dart
import 'errors.dart';

const List<String> _moduleMarkers = <String>[
  '/api/auth',
  '/api/database',
  '/api/storage',
  '/api/ai',
  '/api/functions',
  '/functions/',
];

/// Normalizes a project base URL: trims whitespace and a trailing slash,
/// adds a scheme when missing, and rejects URLs that already include a module
/// path (callers must pass only the project base, e.g. `https://x.insforge.app`).
String normalizeBaseUrl(String input, {bool useHttps = true}) {
  var url = input.trim();
  if (url.isEmpty) {
    throw InsforgeException('baseUrl must not be empty');
  }
  for (final marker in _moduleMarkers) {
    if (url.contains(marker)) {
      throw InsforgeException(
        'baseUrl must not contain module paths (found "$marker"). '
        'Pass only the project base URL.',
      );
    }
  }
  if (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = '${useHttps ? 'https' : 'http'}://$url';
  }
  return url;
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_core/lib/insforge_core.dart`:

```dart
export 'src/url.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_core && dart test test/url_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_core/lib/src/url.dart packages/insforge_core/lib/insforge_core.dart packages/insforge_core/test/url_test.dart
git commit -m "feat(core): add base-URL normalization"
```

---

## Task 8: Date parsing utility

**Files:**
- Create: `packages/insforge_core/lib/src/dates.dart`
- Test: `packages/insforge_core/test/dates_test.dart`
- Modify: `packages/insforge_core/lib/insforge_core.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_core/test/dates_test.dart
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseInsforgeDate', () {
    test('parses ISO8601 with fractional seconds and Z', () {
      final d = parseInsforgeDate('2026-06-08T10:30:00.123Z');
      expect(d, isNotNull);
      expect(d!.isUtc, isTrue);
      expect(d.year, 2026);
      expect(d.millisecond, 123);
    });

    test('parses a date-only value', () {
      final d = parseInsforgeDate('2026-06-08');
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 6);
      expect(d.day, 8);
    });

    test('returns null for null or empty', () {
      expect(parseInsforgeDate(null), isNull);
      expect(parseInsforgeDate(''), isNull);
    });

    test('returns null for an unparseable value', () {
      expect(parseInsforgeDate('not-a-date'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_core && dart test test/dates_test.dart`
Expected: FAIL — `parseInsforgeDate` not defined.

- [ ] **Step 3: Write `dates.dart`**

```dart
// packages/insforge_core/lib/src/dates.dart

/// Parses an InsForge/Postgres timestamp into a UTC [DateTime].
///
/// Handles ISO8601 (with or without fractional seconds / `Z`) and date-only
/// `yyyy-MM-dd` values. Returns null for null, empty, or unparseable input.
DateTime? parseInsforgeDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.toUtc();
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_core/lib/insforge_core.dart`:

```dart
export 'src/dates.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_core && dart test test/dates_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_core/lib/src/dates.dart packages/insforge_core/lib/insforge_core.dart packages/insforge_core/test/dates_test.dart
git commit -m "feat(core): add date parsing utility"
```

---

## Task 9: Logging interceptor

**Files:**
- Create: `packages/insforge_core/lib/src/logging_interceptor.dart`
- Test: `packages/insforge_core/test/logging_interceptor_test.dart`
- Modify: `packages/insforge_core/lib/insforge_core.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_core/test/logging_interceptor_test.dart
import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  test('redacts Authorization and x-api-key in request logs', () {
    final logs = <String>[];
    final interceptor = LoggingInterceptor(LogLevel.info, sink: logs.add);

    final options = RequestOptions(
      path: '/api/auth/sessions',
      method: 'POST',
      headers: <String, dynamic>{
        'Authorization': 'Bearer super-secret-token',
        'x-api-key': 'secret-key',
      },
    );

    interceptor.onRequest(options, RequestInterceptorHandler());

    final joined = logs.join('\n');
    expect(joined, contains('POST'));
    expect(joined, isNot(contains('super-secret-token')));
    expect(joined, isNot(contains('secret-key')));
    expect(joined, contains('Bearer ***'));
  });

  test('logs nothing at LogLevel.none', () {
    final logs = <String>[];
    final interceptor = LoggingInterceptor(LogLevel.none, sink: logs.add);
    interceptor.onRequest(
      RequestOptions(path: '/x', method: 'GET'),
      RequestInterceptorHandler(),
    );
    expect(logs, isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_core && dart test test/logging_interceptor_test.dart`
Expected: FAIL — `LoggingInterceptor` not defined.

- [ ] **Step 3: Write `logging_interceptor.dart`**

```dart
// packages/insforge_core/lib/src/logging_interceptor.dart
import 'package:dio/dio.dart';

import 'options.dart';

/// Sink for log lines. Defaults to nothing (caller supplies one).
typedef LogSink = void Function(String message);

/// Lightweight dio interceptor that logs requests/responses at the configured
/// [LogLevel], redacting sensitive headers.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor(this.level, {LogSink? sink})
      : sink = sink ?? _noop;

  final LogLevel level;
  final LogSink sink;

  static void _noop(String _) {}

  bool get _enabled => level.index >= LogLevel.info.index;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_enabled) {
      sink('→ ${options.method} ${options.uri} headers=${_redact(options.headers)}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (_enabled) {
      sink('← ${response.statusCode} ${response.requestOptions.uri}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (level.index >= LogLevel.error.index && level != LogLevel.none) {
      sink('✗ ${err.response?.statusCode ?? '-'} ${err.requestOptions.uri}: ${err.message}');
    }
    handler.next(err);
  }

  Map<String, dynamic> _redact(Map<String, dynamic> headers) {
    final copy = Map<String, dynamic>.of(headers);
    if (copy.containsKey('Authorization')) copy['Authorization'] = 'Bearer ***';
    if (copy.containsKey('x-api-key')) copy['x-api-key'] = '***';
    return copy;
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_core/lib/insforge_core.dart`:

```dart
export 'src/logging_interceptor.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_core && dart test test/logging_interceptor_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_core/lib/src/logging_interceptor.dart packages/insforge_core/lib/insforge_core.dart packages/insforge_core/test/logging_interceptor_test.dart
git commit -m "feat(core): add redacting logging interceptor"
```

---

## Task 10: `InsforgeHttpClient` — construction + auth header injection

**Files:**
- Create: `packages/insforge_core/lib/src/http_client.dart`
- Test: `packages/insforge_core/test/http_client_auth_test.dart`
- Modify: `packages/insforge_core/lib/insforge_core.dart`

The tests use a tiny custom `HttpClientAdapter` that records request headers and returns canned responses — this avoids coupling tests to a third-party mock-adapter version.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_core/test/http_client_auth_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

/// Records the headers of each request and returns a fixed JSON 200.
class RecordingAdapter implements HttpClientAdapter {
  final List<Map<String, List<String>>> requests = <Map<String, List<String>>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(Map<String, List<String>>.from(options.headers.map(
      (k, v) => MapEntry(k, <String>[v.toString()]),
    )));
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('injects anon key as Bearer when no session token is set', () async {
    final adapter = RecordingAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon-123',
    );
    client.dio.httpClientAdapter = adapter;

    await client.request<dynamic>('GET', '/api/database/records/posts');

    expect(adapter.requests.single['Authorization'], <String>['Bearer anon-123']);
  });

  test('prefers the session access token over the anon key', () async {
    final adapter = RecordingAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon-123',
    );
    client.dio.httpClientAdapter = adapter;
    client.accessToken = 'user-jwt';

    await client.request<dynamic>('GET', '/api/database/records/posts');

    expect(adapter.requests.single['Authorization'], <String>['Bearer user-jwt']);
  });

  test('adds x-api-key when configured', () async {
    final adapter = RecordingAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon-123',
      apiKey: 'apikey-xyz',
    );
    client.dio.httpClientAdapter = adapter;

    await client.request<dynamic>('GET', '/api/storage/buckets');

    expect(adapter.requests.single['x-api-key'], <String>['apikey-xyz']);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_core && dart test test/http_client_auth_test.dart`
Expected: FAIL — `InsforgeHttpClient` not defined.

- [ ] **Step 3: Write `http_client.dart` (construction + auth interceptor + request wrapper)**

```dart
// packages/insforge_core/lib/src/http_client.dart
import 'package:dio/dio.dart';

import 'error_response.dart';
import 'errors.dart';
import 'logging_interceptor.dart';
import 'options.dart';
import 'url.dart';

/// Supplies an access token on demand (e.g. from an external auth provider).
typedef AccessTokenProvider = String? Function();

/// Performs a token refresh and returns the new access token. Throws on failure.
typedef RefreshCallback = Future<String> Function();

const String insforgeUserAgent = 'insforge-flutter/0.1.0';

/// Shared HTTP transport for all InsForge SDK modules.
///
/// Wraps a single [Dio]. Injects `Authorization`/`x-api-key` headers per
/// request, refreshes the access token once on 401 (deduped across concurrent
/// failures — see Task 12), and maps transport errors to [InsforgeException]s.
class InsforgeHttpClient {
  InsforgeHttpClient({
    required String baseUrl,
    required this.anonKey,
    this.apiKey,
    this.options = const InsforgeOptions(),
    this.accessTokenProvider,
    Dio? dio,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        dio = dio ?? Dio() {
    _configure();
  }

  final String baseUrl;
  final String anonKey;
  final String? apiKey;
  final InsforgeOptions options;
  final Dio dio;

  /// Optional external token provider, consulted after the session token.
  AccessTokenProvider? accessTokenProvider;

  String? _accessToken;

  /// The current session access token, or null when signed out.
  String? get accessToken => _accessToken;
  set accessToken(String? value) => _accessToken = value;

  RefreshCallback? _refreshCallback;

  /// Registers the callback used to refresh the access token on a 401.
  void registerRefreshCallback(RefreshCallback callback) {
    _refreshCallback = callback;
  }

  void _configure() {
    dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = options.connectTimeout
      ..receiveTimeout = options.receiveTimeout
      ..headers = <String, dynamic>{
        'User-Agent': insforgeUserAgent,
        ...options.customHeaders,
      }
      ..validateStatus =
          (int? status) => status != null && status >= 200 && status < 300;

    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
    if (options.logLevel != LogLevel.none) {
      dio.interceptors.add(LoggingInterceptor(options.logLevel));
    }
  }

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!options.headers.containsKey('Authorization')) {
      final token = _accessToken ?? accessTokenProvider?.call() ?? anonKey;
      options.headers['Authorization'] = 'Bearer $token';
    }
    if (apiKey != null && !options.headers.containsKey('x-api-key')) {
      options.headers['x-api-key'] = apiKey;
    }
    handler.next(options);
  }

  // 401 refresh handling is implemented in Task 12.
  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    handler.next(err);
  }

  /// Performs a request, mapping transport/HTTP errors to [InsforgeException].
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    ResponseType? responseType,
  }) async {
    try {
      return await dio.request<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: headers,
          responseType: responseType,
        ),
      );
    } on DioException catch (e) {
      throw mapDioError(e);
    }
  }

  /// Maps a [DioException] to the appropriate [InsforgeException].
  InsforgeException mapDioError(DioException e) {
    final response = e.response;
    if (response != null) {
      final data = response.data;
      final parsed = data is Map<String, dynamic>
          ? ErrorResponse.fromJson(data)
          : ErrorResponse(message: data?.toString() ?? 'HTTP ${response.statusCode}');
      return InsforgeHttpException(
        statusCode: response.statusCode ?? -1,
        message: parsed.message,
        error: parsed.error,
        nextActions: parsed.nextActions,
        cause: e,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return InsforgeNetworkException(e.message ?? 'Network error', cause: e);
      default:
        return InsforgeException(e.message ?? 'Unknown error', cause: e);
    }
  }
}
```

- [ ] **Step 4: Export it**

Append to `packages/insforge_core/lib/insforge_core.dart`:

```dart
export 'src/http_client.dart';
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd packages/insforge_core && dart test test/http_client_auth_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_core/lib/src/http_client.dart packages/insforge_core/lib/insforge_core.dart packages/insforge_core/test/http_client_auth_test.dart
git commit -m "feat(core): add InsforgeHttpClient with auth header injection"
```

---

## Task 11: `InsforgeHttpClient` — error mapping

**Files:**
- Test: `packages/insforge_core/test/http_client_error_test.dart`

The implementation already exists (`mapDioError` in Task 10). This task adds the test that locks in the behavior.

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_core/test/http_client_error_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

/// Returns a fixed status + JSON body for every request.
class FixedResponseAdapter implements HttpClientAdapter {
  FixedResponseAdapter(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('maps a non-2xx response to InsforgeHttpException with nextActions',
      () async {
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    client.dio.httpClientAdapter = FixedResponseAdapter(
      404,
      '{"error":"TABLE_NOT_FOUND","message":"No such table","statusCode":404,'
      '"nextActions":"Create the table first."}',
    );

    expect(
      () => client.request<dynamic>('GET', '/api/database/records/nope'),
      throwsA(
        isA<InsforgeHttpException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.error, 'error', 'TABLE_NOT_FOUND')
            .having((e) => e.nextActions, 'nextActions', 'Create the table first.'),
      ),
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it passes**

Run: `cd packages/insforge_core && dart test test/http_client_error_test.dart`
Expected: PASS (implementation from Task 10 already handles this).

- [ ] **Step 3: Commit**

```bash
git add packages/insforge_core/test/http_client_error_test.dart
git commit -m "test(core): cover HTTP error mapping to InsforgeHttpException"
```

---

## Task 12: `InsforgeHttpClient` — single-flight 401 refresh + retry

**Files:**
- Modify: `packages/insforge_core/lib/src/http_client.dart` (replace `_onError`, add refresh helpers)
- Test: `packages/insforge_core/test/http_client_refresh_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// packages/insforge_core/test/http_client_refresh_test.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

/// First request to a protected path returns 401; subsequent requests return
/// 200. Records the Authorization header of every call.
class RefreshScenarioAdapter implements HttpClientAdapter {
  int calls = 0;
  final List<String?> authHeaders = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    authHeaders.add(options.headers['Authorization'] as String?);
    if (calls == 1) {
      return ResponseBody.fromString(
        '{"error":"UNAUTHORIZED","message":"expired","statusCode":401}',
        401,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('refreshes once on 401 and retries with the new token', () async {
    final adapter = RefreshScenarioAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    client.dio.httpClientAdapter = adapter;
    client.accessToken = 'stale-token';

    var refreshCalls = 0;
    client.registerRefreshCallback(() async {
      refreshCalls++;
      client.accessToken = 'fresh-token';
      return 'fresh-token';
    });

    final response =
        await client.request<dynamic>('GET', '/api/database/records/posts');

    expect(response.statusCode, 200);
    expect(refreshCalls, 1);
    expect(adapter.calls, 2);
    expect(adapter.authHeaders[0], 'Bearer stale-token');
    expect(adapter.authHeaders[1], 'Bearer fresh-token');
  });

  test('does not attempt refresh for the refresh endpoint itself', () async {
    final adapter = RefreshScenarioAdapter();
    final client = InsforgeHttpClient(
      baseUrl: 'https://x.insforge.app',
      anonKey: 'anon',
    );
    client.dio.httpClientAdapter = adapter;
    client.registerRefreshCallback(() async => 'should-not-be-called');

    expect(
      () => client.request<dynamic>('POST', '/api/auth/refresh'),
      throwsA(isA<InsforgeHttpException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd packages/insforge_core && dart test test/http_client_refresh_test.dart`
Expected: FAIL — first test gets a thrown 401 (no retry yet); refresh not invoked.

- [ ] **Step 3: Replace `_onError` and add refresh helpers in `http_client.dart`**

Replace the placeholder `_onError` method from Task 10 with the following, and add the two fields/method shown:

```dart
  Future<String>? _inflightRefresh;

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final canRefresh = response?.statusCode == 401 &&
        _refreshCallback != null &&
        !_isAuthExemptPath(err.requestOptions.path) &&
        err.requestOptions.extra['__insforge_retried__'] != true;

    if (!canRefresh) {
      handler.next(err);
      return;
    }

    try {
      final newToken = await _refreshOnce();
      final req = err.requestOptions;
      req.extra['__insforge_retried__'] = true;
      req.headers['Authorization'] = 'Bearer $newToken';
      final retried = await dio.fetch<dynamic>(req);
      handler.resolve(retried);
    } catch (_) {
      handler.next(err);
    }
  }

  Future<String> _refreshOnce() {
    return _inflightRefresh ??=
        _refreshCallback!().whenComplete(() => _inflightRefresh = null);
  }

  bool _isAuthExemptPath(String path) {
    return path.contains('/api/auth/refresh') ||
        path.endsWith('/api/auth/users') ||
        path.endsWith('/api/auth/sessions');
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd packages/insforge_core && dart test test/http_client_refresh_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Run the full core test suite + analyze**

Run: `cd packages/insforge_core && dart test && dart analyze`
Expected: all tests PASS; "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add packages/insforge_core/lib/src/http_client.dart packages/insforge_core/test/http_client_refresh_test.dart
git commit -m "feat(core): single-flight 401 refresh with retry"
```

---

## Task 13: CI workflow

**Files:**
- Create: `.github/workflows/ci.yaml`

- [ ] **Step 1: Write the workflow**

```yaml
# .github/workflows/ci.yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable
      - name: Install dependencies
        run: dart pub get
      - name: Analyze
        run: dart analyze .
      - name: Test insforge_core
        working-directory: packages/insforge_core
        run: dart test
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci: analyze + test on push/PR"
```

---

## Self-Review Notes

- **Spec coverage (core sections of the design doc):** `InsforgeHttpClient` + interceptors (Tasks 10-12), `AuthTokenStore` responsibilities folded into `InsforgeHttpClient` (`accessToken`, `registerRefreshCallback`) — the design's separate `AuthTokenStore` name is realized as fields on the client to avoid a circular dependency with the auth `Session` model; the auth package (Plan 2) writes `accessToken` and registers the refresh callback. `SessionStorage` (Task 5), errors (Tasks 3-4, 11), options (Task 6), URL normalization (Task 7), date handling (Task 8), logging (Task 9), workspace + CI (Tasks 1-2, 13). Covered.
- **Type consistency:** `InsforgeHttpClient.request`, `.accessToken`, `.registerRefreshCallback`, `RefreshCallback`, `AccessTokenProvider`, `InsforgeHttpException(statusCode/error/message/nextActions)`, `ErrorResponse.fromJson`, `SessionStorage`, `InsforgeOptions`, `LogLevel`, `normalizeBaseUrl`, `parseInsforgeDate`, `LoggingInterceptor`, `insforgeUserAgent` are the names later plans must import — keep them stable.
- **Deferred to later plans:** the design's `AuthTokenStore` as a standalone shared class is intentionally collapsed into the client; if a later plan needs a richer shared store it can be extracted then.
