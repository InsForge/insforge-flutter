/// Pure-Dart SDK for InsForge — auth, database, storage, functions, and AI.
library insforge;

// --- core ---
export 'src/core/dates.dart';
export 'src/core/error_response.dart';
export 'src/core/errors.dart';
export 'src/core/http_client.dart';
export 'src/core/logging_interceptor.dart';
export 'src/core/options.dart';
export 'src/core/session_storage.dart';
export 'src/core/url.dart';

// --- auth ---
export 'src/auth/auth_client.dart';
export 'src/auth/auth_options.dart';
export 'src/auth/auth_state.dart';
export 'src/auth/enums.dart';
export 'src/auth/jwt.dart';
export 'src/auth/models/auth_response.dart';
export 'src/auth/models/profile.dart';
export 'src/auth/models/reset_token_response.dart';
export 'src/auth/models/session.dart';
export 'src/auth/models/sign_up_response.dart';
export 'src/auth/models/user.dart';
export 'src/auth/pkce.dart';

// --- database ---
export 'src/database/database_client.dart';
export 'src/database/enums.dart';
export 'src/database/mutation_builder.dart';
export 'src/database/query_builder.dart';
export 'src/database/rpc_builder.dart';

// --- storage ---
export 'src/storage/mime.dart';
export 'src/storage/models.dart';
export 'src/storage/storage_client.dart';
export 'src/storage/storage_file_api.dart';

// --- functions ---
export 'src/functions/functions_client.dart';

// --- ai ---
export 'src/ai/ai_client.dart';
export 'src/ai/errors.dart';
export 'src/ai/models/ai_model.dart';
export 'src/ai/models/chat_chunk.dart';
export 'src/ai/models/chat_completion.dart';
export 'src/ai/models/chat_message.dart';
export 'src/ai/models/content_part.dart';
export 'src/ai/models/embeddings.dart';
export 'src/ai/models/images.dart';
export 'src/ai/models/tool.dart';
export 'src/ai/models/usage.dart';

// --- unified client ---
export 'src/insforge_client.dart';
