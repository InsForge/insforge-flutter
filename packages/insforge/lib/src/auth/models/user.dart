// packages/insforge_auth/lib/src/models/user.dart
import 'package:insforge/insforge.dart';

/// An authenticated InsForge user (mirrors `UserResponse` in auth.yaml).
class User {
  const User({
    required this.id,
    required this.email,
    this.emailVerified = false,
    this.providers = const <String>[],
    this.profile,
    this.metadata,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String email;
  final bool emailVerified;
  final List<String> providers;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Display name read from `profile['name']`, if present.
  String? get name => profile?['name'] as String?;

  /// Avatar URL read from `profile['avatar_url']`, if present.
  String? get avatarUrl => profile?['avatar_url'] as String?;

  factory User.fromJson(Map<String, dynamic> json) {
    final rawProviders = json['providers'];
    final rawProfile = json['profile'];
    final rawMetadata = json['metadata'];
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      emailVerified: json['emailVerified'] as bool? ?? false,
      providers: rawProviders is List
          ? rawProviders.map((dynamic e) => e.toString()).toList()
          : const <String>[],
      profile: rawProfile is Map ? Map<String, dynamic>.from(rawProfile) : null,
      metadata:
          rawMetadata is Map ? Map<String, dynamic>.from(rawMetadata) : null,
      createdAt: parseInsforgeDate(json['createdAt'] as String?),
      updatedAt: parseInsforgeDate(json['updatedAt'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'email': email,
      'emailVerified': emailVerified,
      'providers': providers,
      if (profile != null) 'profile': profile,
      if (metadata != null) 'metadata': metadata,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}
