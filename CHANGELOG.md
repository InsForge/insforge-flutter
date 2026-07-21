# Changelog

All notable changes to the InsForge Dart/Flutter SDK are documented here. This
project follows [Semantic Versioning](https://semver.org) and
[Keep a Changelog](https://keepachangelog.com).

## 0.2.0

Syncs with InsForge JS SDK v1.5.0 (storage: standard PUT create-or-replace
semantics). Requires an InsForge backend that includes the standard-PUT
storage change (InsForge/InsForge#1760); do not run against a pre-change
backend.

### Changed

- **Storage `upload(path, bytes)`** — uploading to a key that already exists
  now replaces the object in place (standard PUT semantics). Previously the
  server silently auto-renamed the key (`photo.png` → `photo (1).png`). The
  method signature is unchanged; the friendly auto-rename UX now lives in the
  InsForge dashboard rather than the API.
- **Storage `uploadAutoKey(filename, bytes)`** — now generates a unique,
  collision-free key client-side (sanitized base + timestamp + random suffix)
  and uploads through the standard `upload` path, so repeated uploads of the
  same file never overwrite each other. The backend no longer mints keys
  server-side.

### Deprecated

- The `upsert` flag on `upload`, `uploadAutoKey`, and `FileOptions` — uploads
  always replace an existing object now, so the flag is a no-op (the
  `x-upsert` header is no longer sent) and will be removed in a future
  release.

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
