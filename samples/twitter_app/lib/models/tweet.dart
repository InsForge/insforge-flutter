// samples/twitter_app/lib/models/tweet.dart
import 'package:insforge/insforge.dart';

/// A tweet plus its joined author profile and like state.
class Tweet {
  Tweet({
    required this.id,
    required this.userId,
    required this.content,
    this.imageUrl,
    this.createdAt,
    this.authorName,
    this.authorAvatarUrl,
    this.likeCount = 0,
  });

  final String id;
  final String userId;
  final String content;
  final String? imageUrl;
  final DateTime? createdAt;
  final String? authorName;
  final String? authorAvatarUrl;
  final int likeCount;

  /// Parses a `tweets` row that joined the author profile, e.g. selected with
  /// `select('*, author:profiles!tweets_user_id_fkey(name, avatar_url)')`.
  factory Tweet.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final authorMap = author is Map ? Map<String, dynamic>.from(author) : null;
    final likes = json['likes'];
    final likeCount = likes is List
        ? likes.length
        : (json['like_count'] as num?)?.toInt() ?? 0;
    return Tweet(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      content: json['content'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      createdAt: parseInsforgeDate(json['created_at'] as String?),
      authorName: authorMap?['name'] as String?,
      authorAvatarUrl: authorMap?['avatar_url'] as String?,
      likeCount: likeCount,
    );
  }
}
