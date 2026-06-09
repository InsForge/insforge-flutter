# Changelog

All notable changes to the InsForge Dart/Flutter SDK are documented here. This
project follows [Semantic Versioning](https://semver.org) and
[Keep a Changelog](https://keepachangelog.com).

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
