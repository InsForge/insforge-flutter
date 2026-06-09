# InsForge Flutter SDK — Integration Tests

A live-backend integration suite for the InsForge Flutter SDK (pure-Dart). It
exercises the real feature packages (`insforge_auth`, `insforge_database`,
`insforge_storage`, `insforge_functions`, `insforge_ai`) against a running
InsForge project and the OpenRouter API.

**The entire suite is environment-driven and skip-safe.** With no integration
environment variables set, every integration test is reported as **SKIPPED**
(0 failures), so it is safe to leave out of normal CI.

## Environment variables

| Variable | Required for | Purpose |
| --- | --- | --- |
| `INSFORGE_INTEGRATION_BASE_URL` | everything (core) | Project base URL, e.g. `https://xxxx.us-east.insforge.app` (trailing slashes are stripped). |
| `INSFORGE_INTEGRATION_ANON_KEY` | everything (core) | Project anon key, used as the default bearer token. |
| `INSFORGE_INTEGRATION_API_KEY` | storage | Project API key. Storage authenticates with `x-api-key`, so the storage HTTP client is built with this. |
| `INSFORGE_INTEGRATION_TEST_EMAIL` | auth, database | Email of a **pre-verified** account. Email verification is enabled, so freshly signed-up users cannot sign in — use a fixed account here. |
| `INSFORGE_INTEGRATION_TEST_PASSWORD` | auth, database | Password for the fixed pre-verified account. |
| `INSFORGE_INTEGRATION_OPENROUTER_KEY` | ai | OpenRouter API key. The AI client is a standalone OpenRouter client and does not go through InsForge. |

### What each file needs

- `connectivity_test.dart` — core (base URL + anon key).
- `auth_test.dart` — sign-up flow needs core; the authenticated flow (fixed
  account sign-in, profile, sign-out) needs core + test email/password.
- `database_test.dart` — core + test email/password (signs in first).
- `storage_test.dart` — core + API key.
- `functions_test.dart` — core.
- `ai_test.dart` — OpenRouter key only.

A test file (or its authenticated subgroup) **skips** when its prerequisites
are absent; it never fails for missing configuration.

## Required backend schema

For full (non-degraded) coverage, the test project should provide:

### Database table `sdk_test`

```sql
CREATE TABLE sdk_test (
  id         serial PRIMARY KEY,
  name       text NOT NULL,
  value      text,
  score      integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);
```

If the table is missing, the database tests degrade to verifying that the SDK
surfaces an `InsforgeHttpException`.

### Storage bucket `public`

A bucket named `public` that accepts authenticated uploads. If unavailable,
the upload/list/download/delete lifecycle tests degrade gracefully (only the
pure `getPublicUrl` and not-found error checks run).

### Edge function `hello-world`

An edge function with the slug `hello-world`. Both a 2xx response and a
structured error are accepted for an existing slug; a clearly non-existent
slug must throw an `InsforgeHttpException`.

## Running

From this directory (`integration_tests/`):

```bash
INSFORGE_INTEGRATION_BASE_URL=https://xxxx.us-east.insforge.app \
INSFORGE_INTEGRATION_ANON_KEY=<anon-key> \
INSFORGE_INTEGRATION_API_KEY=<api-key> \
INSFORGE_INTEGRATION_TEST_EMAIL=<pre-verified-email> \
INSFORGE_INTEGRATION_TEST_PASSWORD=<password> \
INSFORGE_INTEGRATION_OPENROUTER_KEY=<openrouter-key> \
dart test
```

Provide only the subset of variables you have — the rest of the suite simply
skips. With **no** variables set:

```bash
dart test
```

every integration test is reported as skipped.

> First-time setup at the repo root: `flutter pub get` (the workspace includes
> this package).
