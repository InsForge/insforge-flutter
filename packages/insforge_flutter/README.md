# insforge_flutter

Flutter integration for the [InsForge](https://insforge.dev) SDK — secure
on-device session storage and a one-line initializer.

It re-exports the entire pure-Dart
[`insforge`](https://github.com/InsForge/insforge-flutter/tree/main/packages/insforge)
SDK, and adds:

- `SecureSessionStorage` — a `SessionStorage` backed by `flutter_secure_storage`
  (Keychain on iOS, EncryptedSharedPreferences/Keystore on Android).
- `Insforge` — a global singleton you `initialize` once at startup.

```dart
import 'package:insforge_flutter/insforge_flutter.dart';

await Insforge.initialize(
  url: 'https://your.insforge.app',
  anonKey: 'anon-key',
);
final user = Insforge.instance.auth.currentUser;
```

See the [repository root README](https://github.com/InsForge/insforge-flutter)
for the full guide.
