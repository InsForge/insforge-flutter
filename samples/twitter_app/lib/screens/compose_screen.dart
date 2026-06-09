// samples/twitter_app/lib/screens/compose_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:insforge/insforge.dart';

import '../config.dart';
import '../providers.dart';

class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _content = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageName;
  bool _busy = false;
  bool _aiBusy = false;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageName = picked.name;
    });
  }

  /// Streams an AI-suggested caption into the text field via OpenRouter.
  Future<void> _suggestCaption() async {
    setState(() {
      _aiBusy = true;
      _error = null;
      _content.text = '';
    });
    try {
      final ai = ref.read(insforgeClientProvider).ai;
      final stream = ai.chat.completions.createStream(
        ChatCompletionRequest(
          model: 'openai/gpt-4o-mini',
          messages: <ChatMessage>[
            ChatMessage.system(
              'You write short, witty tweet captions under 200 characters.',
            ),
            ChatMessage.user('Suggest a tweet caption for a casual post.'),
          ],
        ),
      );
      await for (final chunk in stream) {
        final delta =
            chunk.choices.isNotEmpty ? chunk.choices.first.delta.content : null;
        if (delta != null) {
          setState(() => _content.text += delta);
        }
      }
    } catch (e) {
      setState(() => _error = 'AI error: $e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _post() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = ref.read(insforgeClientProvider);
    try {
      // `tweets.user_id` references `profiles(id)`, but InsForge does not
      // auto-create a profiles row on signup. Ensure one exists for the
      // current user (idempotent) before posting, so the FK is satisfied and
      // the feed's author join has a name to show.
      await client.database.from('profiles').upsert(
        <String, dynamic>{
          'id': user.id,
          'name': user.name ?? user.email,
        },
        onConflict: 'id',
      ).execute();

      String? imageUrl;
      if (_imageBytes != null) {
        final stored = await client.storage
            .from('tweet-images')
            .uploadAutoKey(_imageName ?? 'image.jpg', _imageBytes!);
        imageUrl = client.storage.from('tweet-images').getPublicUrl(stored.key);
      }
      await client.database.from('tweets').insert(<String, dynamic>{
        'user_id': user.id,
        'content': _content.text.trim(),
        if (imageUrl != null) 'image_url': imageUrl,
      }).execute();
      if (mounted) Navigator.of(context).pop(true);
    } on InsforgeException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New tweet'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _post,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Post'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _content,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: "What's happening?",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_imageBytes!, height: 160),
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('Add image'),
                ),
                const SizedBox(width: 12),
                if (AppConfig.aiEnabled)
                  OutlinedButton.icon(
                    onPressed: _aiBusy ? null : _suggestCaption,
                    icon: _aiBusy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: const Text('Suggest caption'),
                  ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
