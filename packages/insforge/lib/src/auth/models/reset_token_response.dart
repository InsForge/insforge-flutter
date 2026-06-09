// packages/insforge_auth/lib/src/models/reset_token_response.dart
import 'package:insforge/insforge.dart';

/// Response from `POST /api/auth/email/exchange-reset-password-token`:
/// a short-lived reset token usable with `resetPassword`.
class ResetTokenResponse {
  const ResetTokenResponse({required this.token, this.expiresAt});

  final String token;
  final DateTime? expiresAt;

  factory ResetTokenResponse.fromJson(Map<String, dynamic> json) {
    return ResetTokenResponse(
      token: json['token'] as String,
      expiresAt: parseInsforgeDate(json['expiresAt'] as String?),
    );
  }
}
