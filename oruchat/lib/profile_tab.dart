import 'package:flutter/material.dart';

import 'config.dart';
import 'utils.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic>? profile;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    ProfileCache.invalidate(myId);
    final p = await ProfileCache.get(myId);
    if (mounted) setState(() => profile = p);
  }

  Future<void> _update(Map<String, dynamic> values) async {
    setState(() => busy = true);
    try {
      await sb.from('profiles').update(values).eq('id', myId);
      await _load();
    } catch (e) {
      if (mounted) snack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changePhoto() async {
    final source = await chooseImageSource(context);
    if (source == null) return;
    setState(() => busy = true);
    try {
      final url = await pickAndUploadImage(source);
      if (url != null) await _update({'avatar_url': url});
    } catch (e) {
      if (mounted) snack(context, 'Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _editName() async {
    final v = await askText(
      context,
      title: 'Your name',
      initial: (profile?['display_name'] ?? '') as String,
    );
    if (v != null && v.isNotEmpty) await _update({'display_name': v});
  }

  Future<void> _editAbout() async {
    final v = await askText(
      context,
      title: 'About',
      initial: (profile?['about'] ?? '') as String,
    );
    if (v != null && v.isNotEmpty) await _update({'about': v});
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ProfileCache.invalidate(myId);
      await sb.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null) return const Center(child: CircularProgressIndicator());
    final name = (p['display_name'] ?? '') as String;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: busy ? null : _changePhoto,
            child: Stack(
              children: [
                Avatar(name: name, url: p['avatar_url'] as String?, radius: 56),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: purple,
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline, color: purple),
                title: const Text('Name'),
                subtitle: Text(name),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: _editName,
              ),
              ListTile(
                leading: const Icon(Icons.alternate_email, color: purple),
                title: const Text('Username'),
                subtitle: Text('@${p['username']}'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: purple),
                title: const Text('About'),
                subtitle: Text((p['about'] ?? '') as String),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: _editAbout,
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline, color: purple),
                title: const Text('Email'),
                subtitle: Text(sb.auth.currentUser?.email ?? ''),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Log out'),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text('OruChat 1.0', style: TextStyle(color: Colors.black45)),
        ),
      ],
    );
  }
}
