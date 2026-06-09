// packages/insforge_auth/lib/src/models/profile.dart

/// A user's public profile (mirrors `ProfileResponse` in auth.yaml).
class Profile {
  const Profile({required this.id, required this.profile});

  final String id;
  final Map<String, dynamic> profile;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final raw = json['profile'];
    return Profile(
      id: json['id'] as String,
      profile:
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'id': id, 'profile': profile};
  }
}
