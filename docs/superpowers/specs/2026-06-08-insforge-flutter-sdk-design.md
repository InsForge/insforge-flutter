# InsForge Flutter SDK — Design

**Date:** 2026-06-08
**Status:** Approved (design); pending implementation plan
**Author:** brainstormed with Claude Code

## 1. Purpose & Scope

Build a Flutter/Dart SDK for InsForge OSS, organized by module so developers
import only the capabilities they need. The first version (v1) covers:

- **auth** — email/password, OAuth (PKCE), session management, profiles
- **database** — PostgREST-style record CRUD with a fluent query builder
- **storage** — buckets and objects (incl. S3 presigned upload/download)
- **functions** — invoking edge functions
- **ai** — OpenRouter (OpenAI-compatible) chat/images/embeddings, **standalone**

Plus a bundled **sample app** (Twitter-style) that exercises every module as a
reference for developers.

**Out of scope for v1:** realtime, payments, email (these exist in other SDKs
and can be added later as additional packages following the same pattern).

### Reference SDKs

This design mirrors the patterns in the existing InsForge SDKs:
- `../insforge-kotlin` (plugin/module system, query builder, exception model)
- `../insforge-swift` (per-module products, shared header propagation, retry)
- `../InsForge-sdk-js` (current API surface, module naming)
- `../InsForge/openapi/*.yaml` (REST contract: `auth`, `records`, `tables`,
  `storage`, `functions`, `ai`)

## 2. Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Packaging | Monorepo of pub packages (Dart pub workspace + melos) | Truest "import on demand"; mirrors supabase-flutter / Swift per-module products |
| HTTP client | `dio` | First-class interceptors for auth-token injection + single-flight 401 refresh; good multipart/streaming |
| AI target | **OpenRouter direct** (standalone) | Per product direction; `insforge_ai` is a standalone OpenRouter client configured with an OpenRouter key, decoupled from the InsForge backend |
| Error idiom | Throw typed exceptions | Idiomatic Dart; matches Kotlin/Swift and supabase_flutter |
| Session persistence | Default secure storage + pluggable | `SessionStorage` interface in core; `insforge` umbrella ships a `flutter_secure_storage`-backed default; apps may override |
| Sample app | Full Twitter-style app | Most comprehensive reference; exercises all modules |
| Sample state mgmt | Riverpod | Common, testable Flutter state management |

### Note on OpenRouter-direct AI

All shipped InsForge SDKs (JS/Kotlin/Swift) currently route AI through the
InsForge `/api/ai/*` proxy, and the OpenRouter key-provisioning endpoint
(`/api/ai/openrouter/api-key`) is admin-only. The product direction for the
Flutter SDK is to talk to OpenRouter **directly**: `insforge_ai` is a
self-contained OpenRouter client that the developer constructs with an
OpenRouter API key they supply (provisioned out-of-band via the InsForge
dashboard/CLI). This keeps `insforge_ai` usable independently of the rest of
the SDK and avoids embedding InsForge-proxy coupling. The security implication
(an OpenRouter key present on the client) is the developer's responsibility and
should be documented; server-side proxying remains an option they can add via
`insforge_functions`.

## 3. Repository Layout

```
insforge-flutter/
├── pubspec.yaml                 # pub workspace root (resolution: workspace)
├── melos.yaml                   # task runner: bootstrap / analyze / test / publish
├── analysis_options.yaml        # shared lints (very_good_analysis or flutter_lints)
├── packages/
│   ├── insforge_core/           # pure Dart — shared kernel
│   ├── insforge_auth/           # pure Dart — auth
│   ├── insforge_database/       # pure Dart — PostgREST-style CRUD
│   ├── insforge_storage/        # pure Dart — buckets/objects
│   ├── insforge_functions/      # pure Dart — edge function invoke
│   ├── insforge_ai/             # pure Dart — OpenRouter client (standalone)
│   └── insforge/                # umbrella + Flutter integration
└── samples/
    └── twitter_app/             # Flutter app exercising every module
```

**Dependency graph**

- Every feature package depends only on `insforge_core`.
- `insforge_ai` depends on `insforge_core` only for shared errors/logging.
- `insforge` (umbrella) depends on all feature packages **and** Flutter
  (`flutter`, `flutter_secure_storage`). It is the only package that requires
  Flutter; feature packages are pure Dart and unit-testable without a Flutter
  toolchain.
- `samples/twitter_app` depends on `insforge` (path dependency) +
  `url_launcher`, `app_links`, `flutter_riverpod`, `image_picker`.

**Minimum versions:** Dart ≥ 3.5 (for pub workspaces), Flutter ≥ 3.24.

## 4. Component Design

### 4.1 `insforge_core`

The shared kernel. No Flutter dependency.

**`InsforgeHttpClient`** — wraps a `dio.Dio` instance.
- Configuration: `baseUrl`, `anonKey`, optional `apiKey`, `InsforgeOptions`.
- URL normalization: trims trailing `/`, defaults scheme to `https://`,
  validates the base URL does not already contain module paths
  (`/api/auth`, `/api/database`, ...), matching the Kotlin builder.
- Holds the current auth state (see `AuthTokenStore`).
- Interceptors (order matters):
  1. **Auth interceptor** — if no explicit `Authorization` header is set, sets
     `Authorization: Bearer <token>` where `token = accessTokenProvider() ??
     currentAccessToken ?? anonKey`; sets `x-api-key: <apiKey>` when configured.
     (Storage requires `x-api-key`; records accept either scheme; sending both
     is harmless on other routes.)
  2. **Refresh interceptor** — on HTTP 401, invokes a registered
     `RefreshCallback` exactly once across concurrent failures (single-flight
     via a shared `Completer`/lock), then retries the original request with the
     new token. Skips `/api/auth/refresh`, signup (`POST /api/auth/users`), and
     signin (`POST /api/auth/sessions`) to avoid loops.
  3. **Logging interceptor** — gated by `logLevel`; redacts `Authorization` and
     `x-api-key`.

**`AuthTokenStore`** — small mutable holder shared across modules:
`currentSession`, `currentAccessToken`, `setSession()`, `clearSession()`, and
`registerRefreshCallback()`. The auth module is the writer; the http client is a
reader. This is the Dart analogue of Swift's shared `LockIsolated<[String:String]>`
headers.

**`SessionStorage`** (abstract) — `Future<void> write(String, String)`,
`Future<String?> read(String)`, `Future<void> delete(String)`. Plus
`InMemorySessionStorage` for tests/defaults.

**Errors**
- `InsforgeException` (base)
- `InsforgeHttpException(statusCode, error, message, nextActions, cause)`
- `InsforgeAuthException`, `InsforgeNetworkException`,
  `InsforgeSerializationException`
- `ErrorResponse.fromJson` tolerant of both server envelope shapes:
  `{error, message, statusCode, nextActions?}` (auth/records/tables/storage) and
  `{error, details?, code?}` (functions/ai).

**`InsforgeOptions`** — `logLevel`, `customHeaders`, `connectTimeout`,
`receiveTimeout`, optional injected `Dio`.

**Date handling** — JSON helpers that encode ISO8601 and decode tolerant of
fractional seconds and date-only (`yyyy-MM-dd`) values from Postgres.

### 4.2 `insforge_auth`

**`AuthClient(http, storage, {options})`**

Methods (all `Future`):
- `signUp({email, password, name?}) → SignUpResponse`
- `signIn({email, password}) → AuthResponse`
- `signOut()` — clears in-memory + persisted session
- `getCurrentUser() → User`
- `refreshAccessToken() → AuthResponse`
- `sendVerificationEmail(email)`, `verifyEmail({email?, otp}) → AuthResponse`
- `sendPasswordReset(email)`,
  `exchangeResetPasswordToken({email, code}) → ResetTokenResponse`,
  `resetPassword({otp, newPassword})`
- OAuth (PKCE): `getOAuthUrl({provider, redirectUri, codeChallenge}) → String`,
  `signInWithOAuth(...)`, `handleAuthCallback(callbackUri) → AuthResponse`
- `getProfile(userId) → Profile`, `updateProfile(Map) → Profile`

Reactive state:
- `Stream<AuthChangeEvent> onAuthStateChange` (broadcast `StreamController`)
- `User? get currentUser`, `Session? get currentSession`

Behavior:
- Appends `client_type=mobile` to token-issuing calls so `refreshToken` is
  returned in the body (no cookies in Flutter).
- Persists `refreshToken` + `accessToken` + `user` via `SessionStorage` (keys
  `insforge_refresh_token`, `insforge_access_token`, `insforge_user`).
- On construction, restores stored session and proactively refreshes if the JWT
  `exp` is near (decode `exp` claim, refresh ~30s before expiry).
- Registers the refresh callback with `InsforgeHttpClient`.

Models: `User` (id, email, emailVerified, providers, profile, metadata,
timestamps; computed `name`/`avatarUrl`), `Session`, `AuthResponse`,
`SignUpResponse` (`requireEmailVerification`, `hasSession`), `Profile`,
`OAuthProvider` enum (google, github, discord, linkedin, facebook, instagram,
tiktok, apple, x, spotify, microsoft), `ClientType`, `PkceHelper`.

Endpoints (base `${baseUrl}/api/auth`): `POST users`, `POST sessions`,
`POST refresh`, `POST logout`, `GET sessions/current`, `GET oauth/{provider}`,
`POST oauth/exchange`, `PATCH profiles/current`, `GET profiles/{id}`,
`POST email/*`.

### 4.3 `insforge_database`

**`DatabaseClient(http)`**
- `from(table) → QueryBuilder`
- `rpc(fn, {args}) → RpcBuilder`

**`QueryBuilder`** (fluent; accumulates PostgREST query params)
- Filters: `eq, neq, gt, gte, lt, lte, like, ilike, isFilter, inFilter,
  contains, containedBy, or, not, textSearch, filter(col, op, value)`
- Shaping: `select(columns='*')`, `order(col, {ascending})`, `limit`, `offset`,
  `range(from, to)`
- Terminal:
  - `execute() → List<Map<String, dynamic>>`
  - `single() → Map<String, dynamic>` (sets `Accept:
    application/vnd.pgrst.object+json`; maps 406 → validation error)
  - typed convenience `execute<T>(T Function(Map) fromJson) → List<T>`
  - `count({CountType}) → int` (HEAD; reads `Content-Range`/`X-Total-Count`)
- Mutations (return mutation builders exposing `.select()` + `execute()`):
  - `insert(Map | List<Map>)` — body sent as an array (records API requires it)
  - `update(Map)` (carries filters)
  - `delete()` (carries filters)
  - `upsert(Map | List<Map>, {onConflict, ignoreDuplicates})`
  - `.select()` adds `Prefer: return=representation`; upsert adds
    `Prefer: resolution=merge-duplicates|ignore-duplicates` + `on_conflict`.

Endpoints: records at `${baseUrl}/api/database/records/{table}`, rpc at
`${baseUrl}/api/database/rpc/{fn}`.

Supporting types: `CountType` (exact/planned/estimated), `TextSearchType`
(fts/plfts/phfts/wfts), `QueryResult<T>` (data + optional count).

### 4.4 `insforge_storage`

**`StorageClient(http)`**
- `from(bucket) → StorageFileApi` (cached)
- Bucket admin: `listBuckets`, `createBucket(id, {isPublic})`, `updateBucket`,
  `deleteBucket`

**`StorageFileApi`** (operations on one bucket)
- `upload(path, bytes, {contentType, upsert, metadata}) → StoredFile`
- `upload(path, file)` (from a `File`/path)
- `uploadAutoKey(filename, bytes, {...}) → StoredFile`
- `download(path) → Uint8List`
- `list({prefix, limit, offset, search}) → List<StoredFile>`
- `delete(path)` / `delete(List<String>)`
- `getPublicUrl(path)` and `getDownloadStrategy(path, {expiresIn})`
- Strategy flow: `getUploadStrategy(filename, contentType, size) →
  UploadStrategy`; for presigned (S3): multipart POST to the presigned URL using
  a **separate no-auth dio**, with the `file` field **last**; then
  `confirmUpload(objectKey, {size, contentType, etag}) → StoredFile`.

Endpoints (base `${baseUrl}/api/storage`): `buckets`,
`buckets/{b}/objects` (auto-key POST), `buckets/{b}/objects/{key}` (PUT/GET/DELETE),
`buckets/{b}/upload-strategy`, `.../objects/{key}/confirm-upload`,
`.../download-strategy/objects/{key}`. Storage uses the `x-api-key` scheme.

Content-type inferred from file extension when unset (built-in extension→MIME
map). Models: `StoredFile`, `BucketInfo`, `UploadStrategy`, `DownloadStrategy`,
`FileOptions`.

### 4.5 `insforge_functions`

**`FunctionsClient(http, {functionsBaseUrl})`**
- `invoke(slug, {method = 'POST', body, headers, queryParameters}) → dynamic`
  (decoded JSON or raw bytes)
- Execution base path is `${baseUrl}/functions/{slug}` (note: **no** `/api`
  prefix). No SDK-enforced auth (the function enforces its own).

### 4.6 `insforge_ai` (OpenRouter direct, standalone)

**`AIClient(apiKey, {baseUrl = 'https://openrouter.ai/api/v1', dio?})`**
- Own `dio` instance with `Authorization: Bearer <openRouterApiKey>` and
  OpenRouter recommended headers (`HTTP-Referer`, `X-Title` optional).
- `chat.completions.create(ChatCompletionRequest) → ChatCompletionResponse`
  (OpenAI-compatible request/response shapes).
- Streaming: `chat.completions.createStream(...) → Stream<ChatCompletionChunk>`
  via SSE (`data:` line parsing over `dio` `ResponseType.stream`).
- `images.generate(ImageGenerationRequest) → ImageGenerationResponse`
- `embeddings.create(EmbeddingsRequest) → EmbeddingsResponse`
- `listModels() → List<AiModel>`

Models follow the OpenAI/OpenRouter schema (messages with text/image/file
parts, tool calls, usage). Because OpenRouter is OpenAI-compatible, this package
is a thin, well-typed OpenRouter client and has no InsForge coupling beyond
shared error/logging utilities.

### 4.7 `insforge` (umbrella + Flutter)

**`InsforgeClient(baseUrl, anonKey, {InsforgeOptions? options, String? apiKey,
String? openRouterApiKey, SessionStorage? sessionStorage})`**
- Constructs one shared `InsforgeHttpClient`.
- Lazy module getters: `auth`, `database`, `storage`, `functions`. `ai` is
  available when `openRouterApiKey` is provided (throws a helpful error
  otherwise).
- Default `SessionStorage` = `flutter_secure_storage`-backed implementation when
  none supplied.

**Flutter conveniences**
- `Insforge.initialize({...}) → Future<void>` + `Insforge.instance` global
  accessor (supabase_flutter style) for apps that prefer a singleton.
- OAuth/deep-link helpers documented; the actual browser launch + callback
  capture is performed by the app using `url_launcher` + `app_links` (shown in
  the sample) — the SDK provides `getOAuthUrl` + `handleAuthCallback`.

## 5. Cross-cutting Concerns

**Authentication propagation.** A single `InsforgeHttpClient` is shared by all
modules. The auth module writes the current session into `AuthTokenStore`; the
http client's auth interceptor reads it per request. Token precedence:
explicit per-request header → session access token → configured
`accessTokenProvider` → `anonKey`.

**Token refresh.** Reactive single-flight refresh on 401 (deduped) +
proactive refresh before `exp`. Refresh uses `POST /api/auth/refresh` with
`{refreshToken}` (`client_type=mobile`); the new refresh token is persisted.

**Error handling.** Exceptions throughout. Non-2xx responses are decoded into
`ErrorResponse` and thrown as `InsforgeHttpException` (carrying server
`nextActions` when present). Network failures map to `InsforgeNetworkException`.

**Serialization.** Hand-written `fromJson`/`toJson` on model classes (no
build_runner required for v1), snake_case ↔ camelCase handled explicitly. Raw
dynamic data (`Map<String, dynamic>` / `List`) is used where the schema is
open (database records, function payloads).

**Data flow.** app → `InsforgeClient` → module → `InsforgeHttpClient`
(interceptors: auth → refresh → logging) → InsForge backend. AI bypasses
InsForge and talks to OpenRouter directly.

## 6. Testing Strategy

- **Per-package unit tests** with mocked transport (`http_mock_adapter` for
  dio):
  - `insforge_database`: query-builder URL/param construction, Prefer headers,
    count parsing.
  - `insforge_auth`: signup/signin parsing, session persistence, single-flight
    refresh, proactive refresh decision, PKCE challenge generation.
  - `insforge_storage`: direct vs presigned strategy selection, multipart field
    ordering, content-type inference.
  - `insforge_functions`: path construction, method/body pass-through.
  - `insforge_ai`: request shaping, SSE chunk parsing.
  - `insforge_core`: URL normalization, error envelope parsing (both shapes),
    interceptor token precedence.
- **Sample app** for manual/integration verification against a real backend.
- `melos run analyze` and `melos run test` gate CI.

## 7. Sample App — `samples/twitter_app`

Flutter app using **Riverpod**. Singleton `InsforgeClient`. Demonstrates:
- Auth: email/password sign-up (with email verification flow) + OAuth (Google /
  GitHub) via `url_launcher` + `app_links` deep-link callback; session
  persistence; `onAuthStateChange`-driven UI.
- Database: tweet feed with joined author profile
  (`select('*, profiles!tweets_user_id_fkey(*)')` via raw execute), create
  tweet, like/unlike (chained filters + delete), pagination.
- Storage: pick + upload tweet image to a `tweet-images` bucket, store the
  returned URL.
- Functions: invoke an example edge function (e.g. a counter or notification).
- AI: an OpenRouter-powered feature (e.g. "summarize thread" / "suggest a
  caption") with streaming output.

Includes `README` with setup (backend URL, anon key, OpenRouter key, OAuth
redirect scheme) and per-platform deep-link configuration notes.

## 8. Build Order (high level)

1. Workspace scaffolding (pub workspace, melos, lints, CI).
2. `insforge_core` (http client, interceptors, errors, storage interface,
   options).
3. `insforge_auth` (depends on core; unblocks authenticated calls).
4. `insforge_database`.
5. `insforge_storage`.
6. `insforge_functions`.
7. `insforge_ai` (independent; can be built in parallel after core).
8. `insforge` umbrella + Flutter integration (secure-storage default).
9. `samples/twitter_app`.
10. Docs (per-package READMEs + root README + migration/usage guide).

Detailed, ordered, verifiable tasks will be produced by the implementation plan.
