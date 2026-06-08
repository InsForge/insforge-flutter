// packages/insforge_core/lib/src/error_response.dart

/// Parsed representation of an InsForge error response body.
///
/// Tolerant of two server envelope shapes:
/// * auth/records/tables/storage: `{error, message, statusCode, nextActions?}`
/// * functions/ai: `{error, details?, code?}`
class ErrorResponse {
  ErrorResponse({
    this.error,
    required this.message,
    this.statusCode,
    this.nextActions,
  });

  final String? error;
  final String message;
  final int? statusCode;
  final String? nextActions;

  factory ErrorResponse.fromJson(Map<String, dynamic> json) {
    final message =
        (json['message'] ?? json['details'] ?? json['error'] ?? 'Unknown error')
            .toString();
    final code = json['error'] ?? json['code'];
    final rawStatus = json['statusCode'];
    return ErrorResponse(
      error: code?.toString(),
      message: message,
      statusCode: rawStatus is int ? rawStatus : null,
      nextActions: json['nextActions']?.toString(),
    );
  }
}
