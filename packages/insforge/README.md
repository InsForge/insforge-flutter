# insforge

Pure-Dart SDK for [InsForge](https://insforge.dev) — auth, database, storage,
functions, and AI.

This package has no Flutter dependency and runs anywhere Dart runs (CLI,
server, tests). Use the [`InsforgeClient`] to access every module from a single
shared HTTP transport:

```dart
import 'package:insforge/insforge.dart';

final client = InsforgeClient('https://your.insforge.app', 'anon-key');
final rows = await client.database.from('posts').select();
```

By default the client persists the session in memory
([`InMemorySessionStorage`]). For a Flutter app with secure on-device session
storage and a one-line initializer, use the
[`insforge_flutter`](https://github.com/InsForge/insforge-flutter/tree/main/packages/insforge_flutter)
package instead.

See the [repository root README](https://github.com/InsForge/insforge-flutter)
for the full guide.
