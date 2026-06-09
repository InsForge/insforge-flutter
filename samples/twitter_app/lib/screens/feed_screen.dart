// samples/twitter_app/lib/screens/feed_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import '../models/tweet.dart';
import '../providers.dart';
import 'compose_screen.dart';
import 'profile_screen.dart';

const int _pageSize = 20;

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final List<Tweet> _tweets = <Tweet>[];
  // Tweet ids the current user has liked. Empty for now (the sample does not
  // yet read back the per-user like state from the joined `likes(user_id)`).
  final Set<String> _likedTweetIds = <String>{};
  final ScrollController _scroll = ScrollController();
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  DatabaseClient get _db => ref.read(insforgeClientProvider).database;

  Future<void> _refresh() async {
    setState(() {
      _tweets.clear();
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final from = _tweets.length;
      final rows = await _db
          .from('tweets')
          .select(
            '*, author:profiles!tweets_user_id_fkey(name, avatar_url), '
            'likes(user_id)',
          )
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1)
          .execute();
      final page = rows.map(Tweet.fromJson).toList();
      setState(() {
        _tweets.addAll(page);
        _hasMore = page.length == _pageSize;
      });
    } on InsforgeHttpException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike(Tweet tweet, bool currentlyLiked) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      if (currentlyLiked) {
        await _db
            .from('likes')
            .eq('tweet_id', tweet.id)
            .eq('user_id', user.id)
            .delete()
            .execute();
      } else {
        await _db.from('likes').insert(<String, dynamic>{
          'tweet_id': tweet.id,
          'user_id': user.id,
        }).execute();
      }
      await _refresh();
    } on InsforgeHttpException catch (e) {
      _showSnack(e.message);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authClientProvider).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const ComposeScreen()),
          );
          if (created == true) await _refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _error != null
            ? ListView(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error: $_error'),
                  ),
                ],
              )
            : ListView.builder(
                controller: _scroll,
                itemCount: _tweets.length + (_loading ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (index >= _tweets.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final tweet = _tweets[index];
                  // Whether the current user liked this tweet. The sample does
                  // not yet track which user_ids liked a tweet, so this is
                  // always false; a production app would map the joined
                  // `likes.user_id` list against the current user.
                  final liked = _likedTweetIds.contains(tweet.id);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: tweet.authorAvatarUrl != null
                          ? NetworkImage(tweet.authorAvatarUrl!)
                          : null,
                      child: tweet.authorAvatarUrl == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(tweet.authorName ?? 'Anonymous'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(tweet.content),
                        if (tweet.imageUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(tweet.imageUrl!),
                            ),
                          ),
                      ],
                    ),
                    trailing: (user != null)
                        ? IconButton(
                            icon: Icon(
                              liked ? Icons.favorite : Icons.favorite_border,
                            ),
                            color: liked ? Colors.red : null,
                            onPressed: () => _toggleLike(tweet, liked),
                          )
                        : null,
                  );
                },
              ),
      ),
    );
  }
}
