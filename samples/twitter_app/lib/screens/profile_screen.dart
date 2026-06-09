// samples/twitter_app/lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:insforge/insforge.dart';

import '../providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  // This screen reads and writes the `profiles` records table — the same
  // table the feed joins for author name/avatar and that Compose upserts a row
  // into. (InsForge also has a separate auth-side profile via
  // auth.getProfile/updateProfile; the sample standardizes on the `profiles`
  // table so edits are visible there and reflected in the feed.)

  Future<void> _load() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rows = await ref
          .read(insforgeClientProvider)
          .database
          .from('profiles')
          .select('name,bio')
          .eq('id', user.id)
          .limit(1)
          .execute();
      if (rows.isNotEmpty) {
        _name.text = rows.first['name'] as String? ?? '';
        _bio.text = rows.first['bio'] as String? ?? '';
      } else {
        // No profiles row yet — seed the name from the auth user.
        _name.text = user.name ?? '';
      }
    } on InsforgeException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() {
      _saving = true;
      _error = null;
      _info = null;
    });
    try {
      await ref.read(insforgeClientProvider).database.from('profiles').upsert(
        <String, dynamic>{
          'id': user.id,
          'name': _name.text.trim(),
          'bio': _bio.text.trim(),
        },
        onConflict: 'id',
      ).execute();
      setState(() => _info = 'Profile saved.');
    } on InsforgeException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (user != null)
                    Text(
                      user.email,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bio,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Bio'),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  if (_info != null)
                    Text(_info!, style: const TextStyle(color: Colors.green)),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
    );
  }
}
