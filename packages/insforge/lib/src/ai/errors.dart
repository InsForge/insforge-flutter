import 'package:dio/dio.dart';
import 'package:insforge/insforge.dart';

/// Maps a [DioException] from the OpenRouter API to an [InsforgeException].
///
/// OpenRouter returns a **nested** error envelope:
/// `{"error": {"message": "...", "code": 400}}`. The core `ErrorResponse`
/// expects a flat shape, so this package maps it locally.
InsforgeException mapOpenRouterError(DioException e) {
  final response = e.response;
  if (response != null) {
    final statusCode = response.statusCode ?? -1;
    final data = response.data;

    String message = 'HTTP $statusCode';
    String? errorCode;

    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        message = (error['message'] ?? error['type'] ?? message).toString();
        final code = error['code'] ?? error['type'];
        errorCode = code?.toString();
      } else if (error != null) {
        message = error.toString();
      } else if (data['message'] != null) {
        message = data['message'].toString();
      }
    } else if (data is String && data.isNotEmpty) {
      message = data;
    }

    return InsforgeHttpException(
      statusCode: statusCode,
      message: message,
      error: errorCode,
      cause: e,
    );
  }

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return InsforgeNetworkException(e.message ?? 'Network error', cause: e);
    default:
      return InsforgeException(e.message ?? 'Unknown error', cause: e);
  }
}
