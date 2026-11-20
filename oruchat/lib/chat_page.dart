import 'package:flutter/material.dart';

import 'call_service.dart';
import 'config.dart';
import 'utils.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.peer});

  final Map<String, dynamic> peer;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final String peerId = widget.peer['id'] as String;
  late final String chatId = chatIdFor(myId, peerId);
  late final Stream<List<Map<String, dynamic>>> stream = sb
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('chat_id', chatId)
      .order('created_at', ascending: false);

  final input = TextEditingController();
  final scroll = ScrollController();
  bool marking = false;
  bool uploading = false;

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _insert({
    String? body,
    String? mediaUrl,
    required String kind,
  }) async {
    try {
      await sb.from('messages').insert({
        'chat_id': chatId,
        'sender_id': myId,
        'receiver_id': peerId,
        'body': body,
        'media_url': mediaUrl,
        'kind': kind,
      });
    } catch (e) {
      if (mounted) snack(context, 'Message not sent: $e');
    }
  }

  Future<void> sendText() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    await _insert(body: text, kind: 'text');
  }

  Future<void> sendImage() async {
    final source = await chooseImageSource(context);
    if (source == null) return;
    setState(() => uploading = true);
    try {
      final url = await pickAndUploadImage(source);
      if (url != null) await _insert(mediaUrl: url, kind: 'image');
    } catch (e) {
      if (mounted) snack(context, 'Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> markRead(List<Map<String, dynamic>> list) async {
    if (marking) return;
    final hasUnread = list.any(
      (m) => m['receiver_id'] == myId && m['read_at'] == null,
    );
    if (!hasUnread) return;
    marking = true;
    try {
      await sb
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('chat_id', chatId)
          .eq('receiver_id', myId)
          .isFilter('read_at', null);
    } catch (_) {}
    marking = false;
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.peer['display_name'] ?? '') as String;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Avatar(
              name: name,
              url: widget.peer['avatar_url'] as String?,
              radius: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '@${widget.peer['username'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam_rounded, color: purple),
            onPressed: () => CallService.instance.startCall(
              context,
              widget.peer,
              video: true,
            ),
          ),
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.call_rounded, color: purple),
            onPressed: () => CallService.instance.startCall(
              context,
              widget.peer,
              video: false,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError)
                  return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final list = [...snap.data!];
                list.sort(
                  (a, b) => (b['created_at'] as String).compareTo(
                    a['created_at'] as String,
                  ),
                );
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => markRead(list),
                );
                if (list.isEmpty) {
                  return const Center(child: Text('Say hi 👋'));
                }
                return ListView.builder(
                  controller: scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _Bubble(m: list[i]),
                );
              },
            ),
          ),
          if (uploading) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: uploading ? null : sendImage,
                    icon: const Icon(Icons.attach_file_rounded, color: purple),
                  ),
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    backgroundColor: purple,
                    child: IconButton(
                      onPressed: sendText,
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.m});

  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final mine = m['sender_id'] == myId;
    final isImage = m['kind'] == 'image' && m['media_url'] != null;
    final read = m['read_at'] != null;
    final textColor = mine ? Colors.white : ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? purple : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isImage)
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ImageViewPage(url: m['media_url'] as String),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    m['media_url'] as String,
                    width: 230,
                    fit: BoxFit.cover,
                    loadingBuilder: (c, child, progress) => progress == null
                        ? child
                        : const SizedBox(
                            width: 230,
                            height: 160,
                            child: Center(child: CircularProgressIndicator()),
                          ),
                    errorBuilder: (c, e, s) => const SizedBox(
                      width: 230,
                      height: 100,
                      child: Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
              )
            else
              Text(
                (m['body'] ?? '') as String,
                style: TextStyle(color: textColor, fontSize: 16),
              ),
            const SizedBox(height: 2),
            Padding(
              padding: isImage
                  ? const EdgeInsets.fromLTRB(0, 0, 6, 2)
                  : EdgeInsets.zero,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fmtTime(m['created_at'] as String?),
                    style: TextStyle(
                      fontSize: 11,
                      color: mine ? Colors.white70 : Colors.black45,
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      read ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 15,
                      color: read ? const Color(0xFF9DF2FF) : Colors.white70,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
