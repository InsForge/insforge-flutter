/// The InsForge Flutter SDK — unified client and Flutter integration.
library insforge;

// Re-export the public surface of every feature package so apps can
// `import 'package:insforge/insforge.dart';` and get everything.
export 'package:insforge_core/insforge_core.dart';
export 'package:insforge_auth/insforge_auth.dart';
export 'package:insforge_database/insforge_database.dart';
export 'package:insforge_storage/insforge_storage.dart';
export 'package:insforge_functions/insforge_functions.dart';
export 'package:insforge_ai/insforge_ai.dart';

export 'src/insforge.dart';
export 'src/insforge_client.dart';
export 'src/secure_session_storage.dart';
