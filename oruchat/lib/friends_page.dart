import 'package:flutter/material.dart';

import 'chat_page.dart';
import 'config.dart';
import 'utils.dart';

/// Oru user-ine kaanikkunna tile (profile cache vazhi).
class PeerTile extends StatelessWidget {
  const PeerTile({
    super.key,
    required this.peerId,
    this.trailingBuilder,
    this.onTap,
    this.showUsername = true,
  });

  final String peerId;
  final Widget? Function(Map<String, dynamic> p)? trailingBuilder;
  final void Function(Map<String, dynamic> p)? onTap;
  final bool showUsername;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ProfileCache.get(peerId),
      initialData: ProfileCache.peek(peerId),
      builder: (context, snap) {
        final p =
            snap.data ?? {'id': peerId, 'display_name': '...', 'username': ''};
        return ListTile(
          leading: Avatar(
            name: (p['display_name'] ?? '?') as String,
            url: p['avatar_url'] as String?,
          ),
          title: Text(
            (p['display_name'] ?? '') as String,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: showUsername ? Text('@${p['username'] ?? ''}') : null,
          trailing: trailingBuilder?.call(p),
          onTap: onTap == null ? null : () => onTap!(p),
        );
      },
    );
  }
}

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage>
    with SingleTickerProviderStateMixin {
  late final TabController tab = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab,
  );
  late final Stream<List<Map<String, dynamic>>> stream = sb
      .from('friendships')
      .stream(primaryKey: ['id']);

  @override
  void dispose() {
    tab.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Friends',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: tab,
          labelColor: purple,
          indicatorColor: purple,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Requests'),
            Tab(text: 'Find people'),
          ],
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          final rows = snap.data ?? <Map<String, dynamic>>[];
          final friends = <String>[];
          final incoming = <String>[];
          final outgoing = <String>[];
          for (final r in rows) {
            final a = r['requester_id'] as String;
            final b = r['addressee_id'] as String;
            final peer = a == myId ? b : a;
            if (r['status'] == 'accepted') {
              friends.add(peer);
            } else if (r['status'] == 'pending') {
              if (b == myId) {
                incoming.add(peer);
              } else {
                outgoing.add(peer);
              }
            }
          }
          return TabBarView(
            controller: tab,
            children: [
              _friendsList(friends),
              _requestsList(incoming, outgoing),
              const _FindTab(),
            ],
          );
        },
      ),
    );
  }

  Widget _friendsList(List<String> friends) {
    if (friends.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No friends yet.\nOpen "Find people" and send a friend request. Calls work only between friends.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final id in friends)
          PeerTile(
            key: ValueKey('f$id'),
            peerId: id,
            onTap: (p) => openChat(context, peer: p),
            trailingBuilder: (p) => PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'chat') {
                  openChat(context, peer: p);
                } else if (v == 'unfriend') {
                  if (await confirmDialog(
                    context,
                    'Remove ${p['display_name']} from friends?',
                    okLabel: 'Remove',
                  )) {
                    await _run(() => Social.remove(id));
                  }
                } else if (v == 'block') {
                  if (await confirmDialog(
                    context,
                    'Block ${p['display_name']}?',
                    message: 'They will not be able to message or call you.',
                    okLabel: 'Block',
                  )) {
                    await _run(() => Social.block(id));
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'chat', child: Text('Message')),
                PopupMenuItem(value: 'unfriend', child: Text('Remove friend')),
                PopupMenuItem(value: 'block', child: Text('Block')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _requestsList(List<String> incoming, List<String> outgoing) {
    if (incoming.isEmpty && outgoing.isEmpty) {
      return const Center(child: Text('No pending requests'));
    }
    return ListView(
      children: [
        if (incoming.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Received',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
        for (final id in incoming)
          PeerTile(
            key: ValueKey('in$id'),
            peerId: id,
            trailingBuilder: (p) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Accept',
                  icon: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                  ),
                  onPressed: () => _run(() => Social.accept(id)),
                ),
                IconButton(
                  tooltip: 'Decline',
                  icon: const Icon(
                    Icons.cancel_rounded,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _run(() => Social.remove(id)),
                ),
              ],
            ),
          ),
        if (outgoing.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Sent',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
        for (final id in outgoing)
          PeerTile(
            key: ValueKey('out$id'),
            peerId: id,
            trailingBuilder: (p) => TextButton(
              onPressed: () => _run(() => Social.remove(id)),
              child: const Text('Cancel'),
            ),
          ),
      ],
    );
  }
}

class _FindTab extends StatefulWidget {
  const _FindTab();

  @override
  State<_FindTab> createState() => _FindTabState();
}

class _FindTabState extends State<_FindTab> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool loading = false;
  String lastQuery = '';

  @override
  void initState() {
    super.initState();
    search('');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search(String raw) async {
    final q = raw.trim();
    lastQuery = q;
    setState(() => loading = true);
    try {
      final res = await sb.rpc('search_profile_ids', params: {'q': q});
      final ids = <String>[];
      if (res is List) {
        for (final e in res) {
          ids.add(e.toString());
        }
      }
      ProfileCache.lastError = null;
      final map = await ProfileCache.getMany(ids);
      if (!mounted || q != lastQuery) return;
      if (ids.isNotEmpty && map.isEmpty && ProfileCache.lastError != null) {
        snack(context, 'Could not load profiles: ${ProfileCache.lastError}');
      }
      setState(() {
        results = [
          for (final id in ids)
            if (map[id] != null) map[id]!,
        ];
      });
    } catch (e) {
      if (mounted) snack(context, 'Search failed: ${errText(e)}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
    if (mounted) await search(lastQuery);
  }

  Widget _trailing(Map<String, dynamic> p) {
    final id = p['id'] as String;
    switch (p['friend_status']) {
      case 'friends':
        return const Chip(
          label: Text('Friends'),
          visualDensity: VisualDensity.compact,
        );
      case 'pending_out':
        return OutlinedButton(
          onPressed: () => _act(() => Social.remove(id)),
          child: const Text('Requested'),
        );
      case 'pending_in':
        return FilledButton(
          onPressed: () => _act(() => Social.accept(id)),
          style: FilledButton.styleFrom(backgroundColor: purple),
          child: const Text('Accept'),
        );
      default:
        return FilledButton.icon(
          onPressed: () => _act(() => Social.sendRequest(id)),
          style: FilledButton.styleFrom(backgroundColor: purple),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Add'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: controller,
            onChanged: search,
            decoration: InputDecoration(
              hintText: 'Search by name or username',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: results.isEmpty && !loading
              ? const Center(child: Text('No users found'))
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final p = results[i];
                    return ListTile(
                      leading: Avatar(
                        name: (p['display_name'] ?? '?') as String,
                        url: p['avatar_url'] as String?,
                      ),
                      title: Text(
                        (p['display_name'] ?? '') as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text('@${p['username']}'),
                      trailing: _trailing(p),
                      onTap: () => openChat(context, peer: p),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key});

  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  List<String>? ids;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await sb.from('blocks').select().eq('blocker_id', myId);
      final list = [for (final r in rows) r['blocked_id'] as String];
      await ProfileCache.getMany(list);
      if (mounted) setState(() => ids = list);
    } catch (e) {
      if (mounted) {
        setState(() => ids = []);
        snack(context, errText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ids;
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
          ? const Center(child: Text('You have not blocked anyone'))
          : ListView(
              children: [
                for (final id in list)
                  PeerTile(
                    key: ValueKey('b$id'),
                    peerId: id,
                    trailingBuilder: (p) => TextButton(
                      onPressed: () async {
                        try {
                          await Social.unblock(id);
                          await _load();
                        } catch (e) {
                          if (context.mounted) snack(context, errText(e));
                        }
                      },
                      child: const Text('Unblock'),
                    ),
                  ),
              ],
            ),
    );
  }
}
