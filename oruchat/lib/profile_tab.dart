import 'package:flutter/material.dart';

import 'config.dart';
import 'friends_page.dart';
import 'legal_pages.dart';
import 'lock_service.dart';
import 'utils.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  Map<String, dynamic>? profile;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    LockService.instance.addListener(_onLock);
    _load();
  }

  @override
  void dispose() {
    LockService.instance.removeListener(_onLock);
    super.dispose();
  }

  void _onLock() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final p = await ProfileCache.get(myId, fresh: true);
    if (mounted) setState(() => profile = p);
  }

  Future<void> _update(Map<String, dynamic> values) async {
    setState(() => busy = true);
    try {
      await sb.from('profiles').update(values).eq('id', myId);
      await _load();
    } catch (e) {
      if (mounted) snack(context, 'Could not save: ${errText(e)}');
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
      if (mounted) snack(context, 'Photo upload failed: ${errText(e)}');
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

  Future<void> _editUsername() async {
    final v = await askText(
      context,
      title: 'Username',
      hint: '3-20 letters, numbers, _',
      initial: (profile?['username'] ?? '') as String,
    );
    if (v == null || v.isEmpty) return;
    setState(() => busy = true);
    try {
      await sb.rpc('change_username', params: {'new_username': v});
      await _load();
      if (mounted) snack(context, 'Username updated');
    } catch (e) {
      if (mounted) snack(context, errText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    final ok = await confirmDialog(context, 'Log out?', okLabel: 'Log out');
    if (ok) {
      ProfileCache.clearAll();
      await sb.auth.signOut();
    }
  }

  void _go(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null) return const Center(child: CircularProgressIndicator());
    final name = (p['display_name'] ?? '') as String;
    final lock = LockService.instance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (busy) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: busy ? null : _changePhoto,
            child: Stack(
              children: [
                Avatar(name: name, url: p['avatar_url'] as String?, radius: 54),
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: purple,
                    child: Icon(
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
        const SizedBox(height: 16),
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
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: _editUsername,
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
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined, color: purple),
                title: const Text('Privacy'),
                subtitle: const Text(
                  'Profile photo, last seen, online, status, who can message you',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _go(const PrivacyPage()),
              ),
              ListTile(
                leading: const Icon(Icons.people_alt_outlined, color: purple),
                title: const Text('Friends'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _go(const FriendsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded, color: purple),
                title: const Text('Blocked users'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _go(const BlockedPage()),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded, color: purple),
                title: const Text('Chat lock'),
                subtitle: Text(
                  lock.hasPin
                      ? '${lock.lockedCount} locked chat(s). Tap to change PIN.'
                      : 'Create a PIN, then lock chats from the chat menu.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => changePin(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined, color: purple),
                title: const Text('Terms & Conditions'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _go(const TermsPage()),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_rounded, color: purple),
                title: const Text('Support the app'),
                subtitle: const Text('UPI / QR'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _go(const SupportPage()),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: purple),
                title: const Text('About OruChat'),
                subtitle: const Text('Developed by ${AppInfo.studioName}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _go(const AboutPage()),
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
          child: Text(
            'OruChat ${AppInfo.version}',
            style: TextStyle(color: Colors.black45),
          ),
        ),
        const Center(
          child: Text(
            'by ${AppInfo.studioName}',
            style: TextStyle(color: Colors.black38, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  Map<String, dynamic>? row;

  static const Map<String, String> visibilityOptions = {
    'public': 'Everyone (public)',
    'contacts': 'My contacts (friends)',
    'chats': 'My chats',
    'nobody': 'Nobody',
  };

  static const Map<String, String> messageOptions = {
    'public': 'Everyone (public)',
    'friends': 'Friends only',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await sb.from('profiles').select().eq('id', myId).single();
      if (mounted) setState(() => row = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) {
        snack(context, 'Could not load privacy settings: ${errText(e)}');
        setState(() => row = {});
      }
    }
  }

  Future<void> _set(String field, String value) async {
    final old = row?[field];
    setState(() => row = {...?row, field: value});
    try {
      await sb.from('profiles').update({field: value}).eq('id', myId);
      ProfileCache.invalidate(myId);
    } catch (e) {
      if (mounted) {
        setState(() => row = {...?row, field: old});
        snack(context, 'Could not save: ${errText(e)}');
      }
    }
  }

  Widget _tile(
    String title,
    String subtitle,
    String field,
    Map<String, String> options,
  ) {
    final current = (row?[field] ?? 'public') as String;
    return ListTile(
      title: Text(title),
      subtitle: Text(
        options[current] ?? current,
        style: const TextStyle(color: purple, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.arrow_drop_down),
      onTap: () async {
        final v = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(title),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              for (final e in options.entries)
                RadioListTile<String>(
                  value: e.key,
                  groupValue: current,
                  title: Text(e.value),
                  activeColor: purple,
                  onChanged: (x) => Navigator.pop(ctx, x),
                ),
            ],
          ),
        );
        if (v != null && v != current) await _set(field, v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: row == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Who can see my…',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: purple,
                    ),
                  ),
                ),
                _tile(
                  'Profile photo',
                  'Who can see your profile picture',
                  'privacy_photo',
                  visibilityOptions,
                ),
                _tile(
                  'About',
                  'Who can see your about text',
                  'privacy_about',
                  visibilityOptions,
                ),
                _tile(
                  'Last seen',
                  'Who can see when you were last online',
                  'privacy_last_seen',
                  visibilityOptions,
                ),
                _tile(
                  'Online status',
                  'Who can see that you are online now',
                  'privacy_online',
                  visibilityOptions,
                ),
                _tile(
                  'Stories (status)',
                  'Who can see your stories',
                  'privacy_status',
                  visibilityOptions,
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Messages',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: purple,
                    ),
                  ),
                ),
                _tile(
                  'Who can send me messages',
                  'Friends only blocks messages from people you have not accepted as friends',
                  'privacy_messages',
                  messageOptions,
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '"My contacts" = your accepted friends. "My chats" = people you have exchanged messages with. Voice and video calls are always limited to friends. Blocked people can see none of your details.',
                    style: TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ),
              ],
            ),
    );
  }
}
