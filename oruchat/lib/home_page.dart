import 'package:flutter/material.dart';

import 'call_service.dart';
import 'calls_tab.dart';
import 'chat_page.dart';
import 'config.dart';
import 'profile_tab.dart';
import 'stories_tab.dart';
import 'utils.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  static const titles = ['OruChat', 'Stories', 'Calls', 'Profile'];

  @override
  void initState() {
    super.initState();
    CallService.instance.start();
    ProfileCache.get(myId).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    CallService.instance.stop();
    super.dispose();
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
      ),
      body: IndexedStack(
        index: tab,
        children: const [ChatsTab(), StoriesTab(), CallsTab(), ProfileTab()],
      ),
      floatingActionButton: tab == 0
          ? FloatingActionButton(
              backgroundColor: purple,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const NewChatPage())),
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
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: purple),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  late final Stream<List<Map<String, dynamic>>> stream = sb
      .from('messages')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(500);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load chats.\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());

        final rows = [...snap.data!];
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
        final chats = latest.values.toList();

        if (chats.isEmpty) {
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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap the chat button and search for a friend by their username to start talking.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          itemCount: chats.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, i) {
            final m = chats[i];
            final cid = m['chat_id'] as String;
            final mine = m['sender_id'] == myId;
            final peerId = (mine ? m['receiver_id'] : m['sender_id']) as String;
            final count = unread[cid] ?? 0;
            final preview = m['kind'] == 'image'
                ? '📷 Photo'
                : (m['body'] ?? '') as String;
            return FutureBuilder<Map<String, dynamic>>(
              future: ProfileCache.get(peerId),
              initialData: ProfileCache.peek(peerId),
              builder: (context, ps) {
                final p =
                    ps.data ??
                    {'id': peerId, 'display_name': '...', 'avatar_url': null};
                return ListTile(
                  leading: Avatar(
                    name: p['display_name'] ?? '?',
                    url: p['avatar_url'],
                    radius: 26,
                  ),
                  title: Text(
                    p['display_name'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${mine ? 'You: ' : ''}$preview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fmtDayTime(m['created_at'] as String?),
                        style: TextStyle(
                          fontSize: 12,
                          color: count > 0 ? purple : Colors.black54,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(height: 4),
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: purple,
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => ChatPage(peer: p))),
                );
              },
            );
          },
        );
      },
    );
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key});

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final controller = TextEditingController();
  List<Map<String, dynamic>> results = [];
  bool loading = false;

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
    final q = raw.trim().replaceAll(RegExp(r'[,()%*]'), '');
    setState(() => loading = true);
    try {
      var query = sb.from('profiles').select().neq('id', myId);
      if (q.isNotEmpty) {
        query = query.or('username.ilike.%$q%,display_name.ilike.%$q%');
      }
      final data = await query.order('created_at', ascending: false).limit(30);
      if (!mounted) return;
      setState(() => results = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (mounted) snack(context, 'Search failed: $e');
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
            hintText: 'Search by name or username',
            border: InputBorder.none,
          ),
        ),
      ),
      body: loading && results.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : results.isEmpty
          ? const Center(child: Text('No users found'))
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, i) {
                final p = results[i];
                return ListTile(
                  leading: Avatar(
                    name: p['display_name'] ?? '?',
                    url: p['avatar_url'],
                  ),
                  title: Text(p['display_name'] ?? ''),
                  subtitle: Text('@${p['username']}'),
                  onTap: () {
                    ProfileCache.invalidate(p['id'] as String);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => ChatPage(peer: p)),
                    );
                  },
                );
              },
            ),
    );
  }
}
