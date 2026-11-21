import 'package:flutter/material.dart';

import 'chat_page.dart';
import 'config.dart';
import 'friends_page.dart';
import 'utils.dart';

class GroupCache {
  static final Map<String, Map<String, dynamic>> _c = {};

  static Map<String, dynamic>? peek(String id) => _c[id];

  static void put(Map<String, dynamic> g) => _c[g['id'] as String] = g;

  static Future<Map<String, dynamic>> get(
    String id, {
    bool fresh = false,
  }) async {
    final cached = _c[id];
    if (cached != null && !fresh) return cached;
    try {
      final row = await sb.from('groups').select().eq('id', id).maybeSingle();
      if (row != null) {
        _c[id] = row;
        return row;
      }
    } catch (_) {}
    return cached ?? {'id': id, 'name': 'Group', 'avatar_url': null};
  }
}

class PickResult {
  PickResult(this.name, this.ids);
  final String name;
  final List<String> ids;
}

/// Friends-ine thiranjedukkaan (group undaakkaanum member add cheyyaanum).
class FriendPickerPage extends StatefulWidget {
  const FriendPickerPage({
    super.key,
    required this.title,
    required this.actionLabel,
    this.exclude = const <String>{},
    this.askName = false,
  });

  final String title;
  final String actionLabel;
  final Set<String> exclude;
  final bool askName;

  @override
  State<FriendPickerPage> createState() => _FriendPickerPageState();
}

class _FriendPickerPageState extends State<FriendPickerPage> {
  final name = TextEditingController();
  List<String>? friends;
  final Set<String> selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ids = (await Social.friendIds())
          .where((e) => !widget.exclude.contains(e))
          .toList();
      await ProfileCache.getMany(ids);
      if (mounted) setState(() => friends = ids);
    } catch (e) {
      if (mounted) {
        setState(() => friends = []);
        snack(context, errText(e));
      }
    }
  }

  void _done() {
    final n = name.text.trim();
    if (widget.askName && n.isEmpty) {
      snack(context, 'Please enter a group name.');
      return;
    }
    if (selected.isEmpty && !widget.askName) {
      snack(context, 'Select at least one friend.');
      return;
    }
    Navigator.of(context).pop(PickResult(n, selected.toList()));
  }

  @override
  Widget build(BuildContext context) {
    final list = friends;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(onPressed: _done, child: Text(widget.actionLabel)),
        ],
      ),
      body: Column(
        children: [
          if (widget.askName)
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  prefixIcon: Icon(Icons.groups_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          Expanded(
            child: list == null
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Only friends can be added to groups.\nAdd friends first.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final id in list)
                        FutureBuilder<Map<String, dynamic>>(
                          future: ProfileCache.get(id),
                          initialData: ProfileCache.peek(id),
                          builder: (context, snap) {
                            final p =
                                snap.data ??
                                {'display_name': '...', 'username': ''};
                            return CheckboxListTile(
                              value: selected.contains(id),
                              activeColor: purple,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              }),
                              secondary: Avatar(
                                name: (p['display_name'] ?? '?') as String,
                                url: p['avatar_url'] as String?,
                              ),
                              title: Text((p['display_name'] ?? '') as String),
                              subtitle: Text('@${p['username'] ?? ''}'),
                            );
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

Future<void> createGroupFlow(BuildContext context) async {
  final r = await Navigator.of(context).push<PickResult>(
    MaterialPageRoute(
      builder: (_) => const FriendPickerPage(
        title: 'New group',
        actionLabel: 'Create',
        askName: true,
      ),
    ),
  );
  if (r == null || !context.mounted) return;
  try {
    final res = await sb.rpc(
      'create_group',
      params: {'gname': r.name, 'members': r.ids},
    );
    final gid = res.toString();
    final g = await GroupCache.get(gid, fresh: true);
    if (!context.mounted) return;
    await openChat(context, group: g);
  } catch (e) {
    if (context.mounted) snack(context, errText(e));
  }
}

class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({super.key, required this.group});

  final Map<String, dynamic> group;

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late Map<String, dynamic> group = widget.group;
  late final Stream<List<Map<String, dynamic>>> stream = sb
      .from('group_members')
      .stream(primaryKey: ['group_id', 'user_id'])
      .eq('group_id', widget.group['id'] as String);

  String get gid => group['id'] as String;

  Future<void> _rename() async {
    final v = await askText(
      context,
      title: 'Group name',
      initial: (group['name'] ?? '') as String,
    );
    if (v == null || v.isEmpty) return;
    try {
      await sb.rpc('rename_group', params: {'gid': gid, 'new_name': v});
      final g = await GroupCache.get(gid, fresh: true);
      if (mounted) setState(() => group = g);
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _add(Set<String> existing) async {
    final r = await Navigator.of(context).push<PickResult>(
      MaterialPageRoute(
        builder: (_) => FriendPickerPage(
          title: 'Add members',
          actionLabel: 'Add',
          exclude: existing,
        ),
      ),
    );
    if (r == null || !mounted) return;
    try {
      await sb.rpc('add_group_members', params: {'gid': gid, 'members': r.ids});
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _leave() async {
    final ok = await confirmDialog(
      context,
      'Leave this group?',
      okLabel: 'Leave',
    );
    if (!ok || !mounted) return;
    try {
      await sb.rpc('leave_group', params: {'gid': gid});
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (group['name'] ?? 'Group') as String;
    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          final members = snap.data ?? <Map<String, dynamic>>[];
          final ids = {for (final m in members) m['user_id'] as String};
          final iAmAdmin = members.any(
            (m) => m['user_id'] == myId && m['role'] == 'admin',
          );
          return ListView(
            children: [
              const SizedBox(height: 20),
              Center(
                child: Avatar(
                  name: name,
                  radius: 48,
                  icon: Icons.groups_rounded,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Center(
                child: Text(
                  '${members.length} members',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              const SizedBox(height: 12),
              if (iAmAdmin)
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: purple),
                  title: const Text('Rename group'),
                  onTap: _rename,
                ),
              if (iAmAdmin)
                ListTile(
                  leading: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: purple,
                  ),
                  title: const Text('Add members'),
                  onTap: () => _add(ids),
                ),
              const Divider(),
              for (final m in members)
                PeerTile(
                  key: ValueKey('m${m['user_id']}'),
                  peerId: m['user_id'] as String,
                  showUsername: true,
                  trailingBuilder: (p) => m['role'] == 'admin'
                      ? const Chip(
                          label: Text('Admin'),
                          visualDensity: VisualDensity.compact,
                        )
                      : null,
                ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.exit_to_app_rounded,
                  color: Colors.red,
                ),
                title: const Text(
                  'Leave group',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: _leave,
              ),
            ],
          );
        },
      ),
    );
  }
}
