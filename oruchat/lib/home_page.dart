import 'dart:async';

import 'package:flutter/material.dart';

import 'call_service.dart';
import 'calls_tab.dart';
import 'chat_page.dart';
import 'config.dart';
import 'friends_page.dart';
import 'group_pages.dart';
import 'lock_service.dart';
import 'profile_tab.dart';
import 'stories_tab.dart';
import 'utils.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;
  Timer? heartbeat;
  late final Stream<List<Map<String, dynamic>>> friendStream = sb
      .from('friendships')
      .stream(primaryKey: ['id']);

  static const titles = ['OruChat', 'Stories', 'Calls', 'Settings'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CallService.instance.start();
    ProfileCache.get(myId, fresh: true).then((_) {
      if (mounted) setState(() {});
    });
    ClearCache.load().then((_) {
      if (mounted) setState(() {});
    });
    _beat();
    _purge();
    heartbeat = Timer.periodic(const Duration(seconds: 45), (_) => _beat());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    heartbeat?.cancel();
    CallService.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _beat();
      _purge();
      CallService.instance.start();
    }
  }

  Future<void> _beat() async {
    try {
      await sb
          .from('profiles')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', myId);
    } catch (_) {}
  }

  Future<void> _purge() async {
    try {
      await sb.rpc('purge_expired_messages');
    } catch (_) {}
  }

  void _newMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.chat_rounded, color: purple),
              title: const Text('Chat with a friend'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FriendsPage(initialTab: 0),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_rounded, color: purple),
              title: const Text('New group'),
              onTap: () {
                Navigator.pop(ctx);
                createGroupFlow(context);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.person_add_alt_1_rounded,
                color: purple,
              ),
              title: const Text('Find people'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FriendsPage(initialTab: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/brand/logo_icon.png', width: 32, height: 32),
            const SizedBox(width: 10),
            Text(
              titles[tab],
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          if (tab == 0)
            IconButton(
              tooltip: 'Search messages',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchMessagesPage()),
              ),
            ),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: friendStream,
            builder: (context, snap) {
              final rows = snap.data ?? <Map<String, dynamic>>[];
              final pending = rows
                  .where(
                    (r) =>
                        r['status'] == 'pending' && r['addressee_id'] == myId,
                  )
                  .length;
              return IconButton(
                tooltip: 'Friends',
                icon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: const Icon(Icons.people_alt_rounded),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        FriendsPage(initialTab: pending > 0 ? 1 : 0),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: const [ChatsTab(), StoriesTab(), CallsTab(), SettingsTab()],
      ),
      floatingActionButton: tab == 0
          ? FloatingActionButton(
              backgroundColor: purple,
              foregroundColor: Colors.white,
              onPressed: _newMenu,
              child: const Icon(Icons.chat_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        backgroundColor: Colors.white,
        indicatorColor: lavender,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded, color: purple),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.amp_stories_outlined),
            selectedIcon: Icon(Icons.amp_stories_rounded, color: purple),
            label: 'Stories',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call_rounded, color: purple),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded, color: purple),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _ChatItem {
  _ChatItem({
    required this.chatId,
    this.last,
    this.peerId,
    this.group,
    this.unread = 0,
    required this.time,
  });

  final String chatId;
  final Map<String, dynamic>? last;
  final String? peerId;
  final Map<String, dynamic>? group;
  final int unread;
  final String time;
}

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  late final Stream<List<Map<String, dynamic>>> msgStream = sb
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(500);
  late final Stream<List<Map<String, dynamic>>> groupStream = sb
      .from('groups')
      .stream(primaryKey: ['id']);
  Timer? tick;

  @override
  void initState() {
    super.initState();
    LockService.instance.addListener(_onLock);
    tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    LockService.instance.removeListener(_onLock);
    super.dispose();
  }

  void _onLock() {
    if (mounted) setState(() {});
  }

  List<_ChatItem> _build(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> groups,
  ) {
    final rows = messages
        .where(
          (m) => messageVisible(
            m,
            clearedAt: ClearCache.at(m['chat_id'] as String),
          ),
        )
        .toList();
    rows.sort(
      (a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String),
    );
    final latest = <String, Map<String, dynamic>>{};
    final unread = <String, int>{};
    for (final m in rows) {
      final cid = m['chat_id'] as String;
      latest.putIfAbsent(cid, () => m);
      if (m['receiver_id'] == myId && m['read_at'] == null) {
        unread[cid] = (unread[cid] ?? 0) + 1;
      }
    }
    final groupById = {for (final g in groups) g['id'] as String: g};
    for (final g in groups) {
      GroupCache.put(g);
    }
    final items = <_ChatItem>[];
    final seenGroups = <String>{};
    for (final e in latest.entries) {
      final m = e.value;
      if (m['group_id'] != null) {
        final gid = m['group_id'] as String;
        final g = groupById[gid];
        if (g == null) continue;
        seenGroups.add(gid);
        items.add(
          _ChatItem(
            chatId: e.key,
            last: m,
            group: g,
            unread: unread[e.key] ?? 0,
            time: m['created_at'] as String,
          ),
        );
      } else {
        final mine = m['sender_id'] == myId;
        final peerId = (mine ? m['receiver_id'] : m['sender_id']) as String;
        items.add(
          _ChatItem(
            chatId: e.key,
            last: m,
            peerId: peerId,
            unread: unread[e.key] ?? 0,
            time: m['created_at'] as String,
          ),
        );
      }
    }
    for (final g in groups) {
      final gid = g['id'] as String;
      if (seenGroups.contains(gid)) continue;
      final cid = groupChatId(gid);
      final cleared = ClearCache.at(cid);
      if (cleared != null) {
        final created = DateTime.tryParse((g['created_at'] ?? '') as String);
        if (created != null && !created.isAfter(cleared)) continue;
      }
      items.add(
        _ChatItem(
          chatId: cid,
          group: g,
          time: (g['created_at'] ?? '') as String,
        ),
      );
    }
    items.sort((a, b) => b.time.compareTo(a.time));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: msgStream,
      builder: (context, msgSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: groupStream,
          builder: (context, groupSnap) {
            if (msgSnap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load chats.\n${msgSnap.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!msgSnap.hasData)
              return const Center(child: CircularProgressIndicator());
            final items = _build(
              msgSnap.data!,
              groupSnap.data ?? <Map<String, dynamic>>[],
            );

            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/brand/logo_icon.png', width: 90),
                      const SizedBox(height: 16),
                      const Text(
                        'No chats yet',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tap the chat button to message a friend, find people, or start a group.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
              itemBuilder: (context, i) => _tile(context, items[i]),
            );
          },
        );
      },
    );
  }

  Widget _tile(BuildContext context, _ChatItem it) {
    final locked = LockService.instance.isLocked(it.chatId);
    final m = it.last;
    final mine = m != null && m['sender_id'] == myId;
    final preview = locked
        ? '🔒 Locked chat'
        : (m == null
              ? 'Group created'
              : '${mine ? 'You: ' : ''}${previewOf(m)}');

    Widget build(Map<String, dynamic>? p) {
      final name = it.group != null
          ? (it.group!['name'] ?? 'Group') as String
          : (p?['display_name'] ?? '...') as String;
      final url = it.group != null
          ? it.group!['avatar_url'] as String?
          : p?['avatar_url'] as String?;
      return ListTile(
        leading: Avatar(
          name: name,
          url: url,
          radius: 26,
          icon: it.group != null ? Icons.groups_rounded : null,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (locked)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.lock_rounded,
                  size: 15,
                  color: Colors.black45,
                ),
              ),
          ],
        ),
        subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmtDayTime(it.time),
              style: TextStyle(
                fontSize: 12,
                color: it.unread > 0 ? purple : Colors.black54,
              ),
            ),
            if (it.unread > 0) ...[
              const SizedBox(height: 4),
              CircleAvatar(
                radius: 10,
                backgroundColor: purple,
                child: Text(
                  '${it.unread}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ],
        ),
        onTap: () {
          if (it.group != null) {
            openChat(context, group: it.group);
          } else {
            openChat(
              context,
              peer:
                  p ?? {'id': it.peerId, 'display_name': name, 'username': ''},
            );
          }
        },
      );
    }

    if (it.group != null) return build(null);
    return FutureBuilder<Map<String, dynamic>>(
      future: ProfileCache.get(it.peerId!),
      initialData: ProfileCache.peek(it.peerId!),
      builder: (context, ps) => build(ps.data),
    );
  }
}

/// Ellaa chats-ilum message search.
class SearchMessagesPage extends StatefulWidget {
  const SearchMessagesPage({super.key});

  @override
  State<SearchMessagesPage> createState() => _SearchMessagesPageState();
}

class _SearchMessagesPageState extends State<SearchMessagesPage> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool loading = false;
  String lastQuery = '';

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search(String raw) async {
    final q = raw.trim().replaceAll(RegExp(r'[%_]'), '');
    lastQuery = q;
    if (q.length < 2) {
      setState(() => results = []);
      return;
    }
    setState(() => loading = true);
    try {
      final data = await sb
          .from('messages')
          .select()
          .eq('once', false)
          .ilike('body', '%$q%')
          .order('created_at', ascending: false)
          .limit(60);
      if (!mounted || q != lastQuery) return;
      final list = List<Map<String, dynamic>>.from(data)
          .where(
            (m) => messageVisible(
              m,
              clearedAt: ClearCache.at(m['chat_id'] as String),
            ),
          )
          .where((m) => !LockService.instance.isLocked(m['chat_id'] as String))
          .toList();
      final ids = <String>{};
      for (final m in list) {
        if (m['group_id'] == null) {
          ids.add(
            (m['sender_id'] == myId ? m['receiver_id'] : m['sender_id'])
                as String,
          );
        }
      }
      await ProfileCache.getMany(ids.toList());
      if (mounted) setState(() => results = list);
    } catch (e) {
      if (mounted) snack(context, 'Search failed: ${errText(e)}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          autofocus: true,
          onChanged: search,
          decoration: const InputDecoration(
            hintText: 'Search messages',
            border: InputBorder.none,
          ),
        ),
      ),
      body: Column(
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      controller.text.trim().length < 2
                          ? 'Type at least 2 letters'
                          : 'No messages found',
                    ),
                  )
                : ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = results[i];
                      final isGroup = m['group_id'] != null;
                      final other = isGroup
                          ? null
                          : (m['sender_id'] == myId
                                    ? m['receiver_id']
                                    : m['sender_id'])
                                as String;
                      final prof = other == null
                          ? null
                          : ProfileCache.peek(other);
                      final g = isGroup
                          ? GroupCache.peek(m['group_id'] as String)
                          : null;
                      final name = isGroup
                          ? ((g?['name'] ?? 'Group') as String)
                          : ((prof?['display_name'] ?? '...') as String);
                      return ListTile(
                        leading: Avatar(
                          name: name,
                          url: prof?['avatar_url'] as String?,
                          icon: isGroup ? Icons.groups_rounded : null,
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          (m['body'] ?? '') as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          fmtDayTime(m['created_at'] as String?),
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => openChatForMessage(context, m),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
