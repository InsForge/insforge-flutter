# Contributing to the InsForge Dart/Flutter SDK

Thanks for helping improve the SDK! This guide covers the repository layout,
local setup, testing, and the conventions we follow.

## Repository layout

This is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces) (a
monorepo resolved together):

```
packages/
  insforge/            # pure-Dart SDK (auth, database, storage, functions, ai)
  insforge_flutter/    # Flutter layer: SecureSessionStorage + Insforge singleton
integration_tests/     # live, against-a-real-project tests (opt-in via env vars)
samples/
  twitter_app/         # full Flutter sample app
```

`insforge_flutter` depends on and re-exports `insforge`.

## Prerequisites

- Flutter ≥ 3.24 (bundles a compatible Dart ≥ 3.5). `flutter --version` and
  `dart --version` must both work.
- Because the workspace contains a Flutter package, resolve it with **`flutter
  pub get`** (not `dart pub get`) from the repo root.

```bash
flutter pub get
```

## Running the checks

Everything must pass before a change is merged.

```bash
# Static analysis (whole workspace)
dart analyze .

# Pure-Dart unit tests
cd packages/insforge && dart test

# Flutter unit tests
cd packages/insforge_flutter && flutter test
```

Formatting must be clean:

```bash
dart format .
```

The analyzer config (`analysis_options.yaml`) enables stricter lints —
notably `require_trailing_commas`, `prefer_single_quotes`, and
`avoid_print`. CI runs `dart analyze .` plus every package's tests and fails
on any issue.

## Integration tests (live backend)

`integration_tests/` exercises the SDK against a real InsForge project. With no
environment variables set, **every test skips** — so it's safe in normal CI.
To run it, provide a project and a pre-verified account:

```bash
cd integration_tests
INSFORGE_INTEGRATION_BASE_URL=https://<project>.insforge.app \
INSFORGE_INTEGRATION_ANON_KEY=<anon-key> \
INSFORGE_INTEGRATION_TEST_EMAIL=<verified-account-email> \
INSFORGE_INTEGRATION_TEST_PASSWORD=<password> \
INSFORGE_INTEGRATION_API_KEY=<project-api-key> \         # for storage
INSFORGE_INTEGRATION_OPENROUTER_KEY=<openrouter-key> \   # for ai
dart test
```

See `integration_tests/README.md` for the required backend schema (the
`sdk_test` table, a `public` bucket, and a `hello-world` function). Never
commit real keys — keep them in your shell.

## Coding conventions

- **Models** use hand-written `fromJson`/`toJson` (no codegen). Be tolerant of
  missing/optional fields the backend may omit.
- **Errors**: throw the typed `InsforgeException` hierarchy; don't return
  `{data, error}` tuples.
- **No Flutter in `insforge`**: the `insforge` package must stay pure Dart so it
  runs under `dart test`. Anything needing Flutter belongs in
  `insforge_flutter`.
- Keep the public API stable; document deviations from the backend contract.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org):

```
feat(database): accumulate multiple filters per column
fix(auth): tolerate signUp response without a user
test(integration): cover the email verification flow
docs(readme): document the AI module
```

Scopes are typically a module name (`auth`, `database`, `storage`,
`functions`, `ai`, `core`) or `sample` / `integration` / `ci`.

## Pull requests

1. Branch off `main`.
2. Make the change with tests; keep `dart analyze .` and all suites green.
3. If a change is driven by real backend behavior, add or update an integration
   test that proves it.
4. Update `CHANGELOG.md` under the unreleased/next version.
5. Open a PR describing the change and how you verified it.

By contributing, you agree that your contributions are licensed under the
project's [Apache License 2.0](LICENSE).
