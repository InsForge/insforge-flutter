# Changelog

All notable changes to the InsForge Dart/Flutter SDK are documented here. This
project follows [Semantic Versioning](https://semver.org) and
[Keep a Changelog](https://keepachangelog.com).

## 0.2.0

Sync with [InsForge-sdk-js v1.5.1](https://github.com/InsForge/InsForge-sdk-js/releases/tag/v1.5.1).

### Added

- **Auth — passwordless email OTP sign-in** (`insforge`):
  - `AuthClient.signInWithOtp(email: ...)` — requests a 6-digit sign-in code
    via `POST /api/auth/email/send-otp`. The server response is intentionally
    generic whether or not an account exists (enumeration-safe).
  - `AuthClient.verifyOtp(email: ..., otp: ..., name: ...)` — verifies the
    code via `POST /api/auth/sessions` (`method: 'otp'`) and establishes,
    persists, and emits a session like every other token-issuing flow. `name`
    sets the display name only when a new user is created.
- **Storage** — `DeleteObjectResult` model (`key`,
  `status: deleted | notFound | failed`, optional `message`).

### Changed

- **Storage** — `StorageFileApi.deleteAll(paths)` now issues a single batch
  request (`DELETE /api/storage/buckets/{bucket}/objects` with `{keys}`,
  maximum 1000 keys) instead of one DELETE per path, and returns
  `List<DeleteObjectResult>` (one result per key) instead of `void`.

## 0.1.0

Initial release.

### Added

- **`insforge` (pure Dart)** — the shared, framework-agnostic SDK:
  - `InsforgeHttpClient`: auth-header injection, single-flight 401 token
    refresh, typed `InsforgeException` error mapping.
  - **Auth**: email/password sign-up & sign-in, code-based email verification,
    PKCE OAuth (`getOAuthUrl` / `handleOAuthCallback`), sessions with proactive
    refresh, profiles, and a broadcast `onAuthStateChange` stream.
  - **Database**: PostgREST-style query builder — filters (including multiple
    AND-ed conditions per column), ordering, pagination, `single`/`count`,
    `insert`/`update`/`delete`/`upsert`, and RPC.
  - **Storage**: buckets and objects — multipart upload, download, list,
    delete, public URLs, the upload/download strategy flow, and presigned S3
    `uploadLarge`.
  - **Functions**: edge-function invocation across all HTTP verbs.
  - **AI**: standalone OpenRouter (OpenAI-compatible) client — chat
    completions with SSE streaming, embeddings, images, and model listing.
  - `SessionStorage` interface + `InMemorySessionStorage`.
  - `InsforgeClient` aggregator wiring every module onto one shared transport.
- **`insforge_flutter`** — the Flutter integration layer:
  - `SecureSessionStorage` backed by `flutter_secure_storage`.
  - `Insforge.initialize(...)` / `Insforge.instance` singleton that restores a
    persisted session before the first frame.
