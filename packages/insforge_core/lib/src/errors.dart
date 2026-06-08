// packages/insforge_core/lib/src/errors.dart

/// Base class for all errors thrown by the InsForge SDK.
class InsforgeException implements Exception {
  InsforgeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'InsforgeException: $message';
}

/// Thrown when the backend returns a non-2xx HTTP response.
class InsforgeHttpException extends InsforgeException {
  InsforgeHttpException({
    required this.statusCode,
    required String message,
    this.error,
    this.nextActions,
    Object? cause,
  }) : super(message, cause: cause);

  /// HTTP status code (e.g. 401, 404).
  final int statusCode;

  /// Server error code/string (e.g. `AUTH_INVALID_CREDENTIALS`).
  final String? error;

  /// Server-suggested remediation, when provided.
  final String? nextActions;

  @override
  String toString() {
    final actions = nextActions != null ? ' | nextActions: $nextActions' : '';
    return 'InsforgeHttpException($statusCode, error: $error): $message$actions';
  }
}

/// Thrown for authentication-specific failures.
class InsforgeAuthException extends InsforgeException {
  InsforgeAuthException(super.message, {super.cause});
}

/// Thrown for transport-level failures (timeouts, no connection).
class InsforgeNetworkException extends InsforgeException {
  InsforgeNetworkException(super.message, {super.cause});
}

/// Thrown when a response body cannot be parsed into the expected shape.
class InsforgeSerializationException extends InsforgeException {
  InsforgeSerializationException(super.message, {super.cause});
}
