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

## Versioning & releasing

`insforge` and `insforge_flutter` are released **in lockstep** — they always
share the same version number. The version lives in three places that must stay
in sync:

- `packages/insforge/pubspec.yaml` → `version:`
- `packages/insforge_flutter/pubspec.yaml` → `version:` **and** its
  `insforge: ^<version>` dependency constraint
- `packages/insforge/lib/src/core/version.dart` → `insforgeSdkVersion`
  (a generated constant; the runtime `User-Agent` is `InsForge-Dart/<version>`)

Don't edit these by hand — use the tool, which updates all of them at once:

```bash
dart run tool/set_version.dart 0.2.0   # set the version everywhere
dart run tool/set_version.dart --check # verify they're in sync (CI runs this)
```

`version.dart` is generated; never edit it directly. CI fails if the three drift
apart.

### Release checklist

1. `dart run tool/set_version.dart <new-version>`.
2. Add a `## <new-version>` section to each package's `CHANGELOG.md`.
3. Commit, open a PR, merge to `main`.
4. Tag and publish the core package:
   ```bash
   git tag -a insforge-v<new-version> -m "insforge v<new-version>"
   git push origin insforge-v<new-version>
   ```
5. Wait until that exact `insforge` version is visible on pub.dev.
6. Tag and publish the Flutter package from the same release commit:
   ```bash
   git tag -a insforge_flutter-v<new-version> -m "insforge_flutter v<new-version>"
   git push origin insforge_flutter-v<new-version>
   ```

Both tags trigger package-specific GitHub Actions workflows that publish through
pub.dev automated publishing (OIDC). No pub.dev token is stored in GitHub. Do
not push the `insforge_flutter` tag before the matching `insforge` version is
available, because the Flutter package depends on it. Each stable package tag
creates a GitHub Release after pub.dev publication succeeds; prerelease tags
publish to pub.dev without creating a GitHub Release.

> Note on 0.x: under SemVer, `^0.1.0` means `>=0.1.0 <0.2.0`. Bumping the minor
> (e.g. `0.1.x → 0.2.0`) is a breaking change, and the tool updates
> `insforge_flutter`'s `insforge: ^…` constraint accordingly so it picks up the
> new core.

## Pull requests

1. Branch off `main`.
2. Make the change with tests; keep `dart analyze .` and all suites green.
3. If a change is driven by real backend behavior, add or update an integration
   test that proves it.
4. Update `CHANGELOG.md` under the unreleased/next version.
5. Open a PR describing the change and how you verified it.

By contributing, you agree that your contributions are licensed under the
project's [Apache License 2.0](LICENSE).
