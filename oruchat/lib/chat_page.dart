import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import 'advanced_features.dart';

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
  bool viewOnceNext = false;
  int disappearingSeconds = 0;
  final AudioRecorder recorder = AudioRecorder();
  bool recording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadChatPreferences();
      final ok = await ChatLock.unlock(context, chatId);
      if (!ok && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    recorder.dispose();
    super.dispose();
  }

  Future<void> _loadChatPreferences() async {
    try {
      final row = await sb.from('chat_preferences').select('disappearing_seconds').eq('user_id', myId).eq('chat_id', chatId).maybeSingle();
      if (mounted && row != null) setState(() => disappearingSeconds = (row['disappearing_seconds'] as num).toInt());
    } catch (_) {}
  }

  Future<void> _insert({
    String? body,
    String? mediaUrl,
    required String kind,
    bool? viewOnce,
  }) async {
    try {
      await sb.from('messages').insert({
        'chat_id': chatId,
        'sender_id': myId,
        'receiver_id': peerId,
        'body': body,
        'media_url': mediaUrl,
        'kind': kind,
        'view_once': viewOnce ?? viewOnceNext,
        'expires_at': disappearingSeconds > 0 ? DateTime.now().toUtc().add(Duration(seconds: disappearingSeconds)).toIso8601String() : null,
      });
      if (viewOnce == null) viewOnceNext = false;
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
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 95);
      if (picked == null || !mounted) return;
      final original = await picked.readAsBytes();
      final filtered = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => StoryFilterPage(bytes: original)));
      if (filtered == null) return;
      final path = '$myId/${DateTime.now().microsecondsSinceEpoch}_chat.jpg';
      await sb.storage.from('media').uploadBinary(path, filtered, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      await _insert(mediaUrl: sb.storage.from('media').getPublicUrl(path), kind: 'image');
    } catch (e) {
      if (mounted) snack(context, 'Photo upload failed: $e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }


  Future<void> sendDocument() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    final bytes = f.bytes;
    if (bytes == null) { snack(context, 'Could not read selected file'); return; }
    setState(() => uploading = true);
    try {
      final path = '$myId/${DateTime.now().microsecondsSinceEpoch}_${f.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
      await sb.storage.from('media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: f.extension == 'pdf' ? 'application/pdf' : 'application/octet-stream'));
      final url = sb.storage.from('media').getPublicUrl(path);
      await _insert(body: f.name, mediaUrl: url, kind: 'file');
    } catch (e) { if (mounted) snack(context, 'File upload failed: $e'); }
    finally { if (mounted) setState(() => uploading = false); }
  }

  Future<void> sendVideo() async {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    setState(() => uploading = true);
    try {
      final bytes = await x.readAsBytes();
      final path = '$myId/${DateTime.now().microsecondsSinceEpoch}.mp4';
      await sb.storage.from('media').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'video/mp4'));
      await _insert(body: x.name, mediaUrl: sb.storage.from('media').getPublicUrl(path), kind: 'video');
    } catch (e) { if (mounted) snack(context, 'Video upload failed: $e'); }
    finally { if (mounted) setState(() => uploading = false); }
  }

  Future<void> toggleVoiceRecording() async {
    if (recording) {
      final path = await recorder.stop();
      if (mounted) setState(() => recording = false);
      if (path == null) return;
      setState(() => uploading = true);
      try {
        final bytes = await File(path).readAsBytes();
        final key = '$myId/${DateTime.now().microsecondsSinceEpoch}.m4a';
        await sb.storage.from('media').uploadBinary(key, bytes, fileOptions: const FileOptions(contentType: 'audio/mp4'));
        await _insert(body: 'Voice message', mediaUrl: sb.storage.from('media').getPublicUrl(key), kind: 'audio');
      } catch (e) { if (mounted) snack(context, 'Voice upload failed: $e'); }
      finally { if (mounted) setState(() => uploading = false); }
    } else {
      try {
        if (!await recorder.hasPermission()) { snack(context, 'Microphone permission is required'); return; }
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/oru_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        if (mounted) setState(() => recording = true);
      } catch (e) { if (mounted) snack(context, 'Could not start recording: $e'); }
    }
  }

  Future<void> messageOptions() async {
    final action = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.visibility_off), title: Text(viewOnceNext ? 'Disable view-once for next message' : 'Send next message as view-once'), onTap: () => Navigator.pop(ctx, 'once')),
      ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Disappearing messages'), subtitle: Text(disappearingSeconds == 0 ? 'Off' : 'Enabled'), onTap: () => Navigator.pop(ctx, 'expiry')),
      ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Lock this chat'), onTap: () => Navigator.pop(ctx, 'lock')),
      ListTile(leading: const Icon(Icons.group_outlined), title: const Text('Open group chats'), onTap: () => Navigator.pop(ctx, 'groups')),
    ])));
    if (action == 'once') setState(() => viewOnceNext = !viewOnceNext);
    if (action == 'expiry') {
      final seconds = await MessageExpiry.choose(context);
      if (seconds != null) {
        try {
          await sb.from('chat_preferences').upsert({'user_id': myId, 'chat_id': chatId, 'disappearing_seconds': seconds}, onConflict: 'user_id,chat_id');
          if (mounted) setState(() => disappearingSeconds = seconds);
        } catch (e) { if (mounted) snack(context, 'Could not save timer: $e'); }
      }
    }
    if (action == 'lock') await ChatLock.configure(context, chatId);
    if (action == 'groups' && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupsPage()));
  }

  Future<void> openViewOnce(Map<String, dynamic> m) async {
    try {
      final data = await sb.rpc('consume_view_once_message', params: {'message_id': m['id']});
      final row = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ViewOnceViewer(message: row)));
    } catch (e) { if (mounted) snack(context, 'This view-once message is no longer available'); }
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
          IconButton(tooltip: 'Chat options', onPressed: messageOptions, icon: const Icon(Icons.more_vert)),
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
                  itemBuilder: (context, i) => GestureDetector(onTap: list[i]['view_once'] == true && list[i]['receiver_id'] == myId ? () => openViewOnce(list[i]) : null, child: _Bubble(m: list[i])),
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
                  IconButton(onPressed: uploading ? null : sendDocument, icon: const Icon(Icons.attach_file_rounded, color: purple)),
                  IconButton(onPressed: uploading ? null : sendImage, icon: const Icon(Icons.image_outlined, color: purple)),
                  IconButton(onPressed: uploading ? null : sendVideo, icon: const Icon(Icons.video_library_outlined, color: purple)),
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
                  IconButton(onPressed: uploading ? null : toggleVoiceRecording, icon: Icon(recording ? Icons.stop_circle : Icons.mic, color: recording ? Colors.red : purple)),
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
    final isVideo = m['kind'] == 'video' && m['media_url'] != null;
    final isAudio = m['kind'] == 'audio' && m['media_url'] != null;
    final isFile = m['kind'] == 'file' && m['media_url'] != null;
    final isOnce = m['view_once'] == true;
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
            if (isOnce)
              Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.visibility_off, color: Colors.white70), const SizedBox(width: 8), Text(mine ? 'View-once message sent' : 'View once • Tap to open', style: TextStyle(color: textColor))])
            else if (isAudio)
              _AudioMessage(url: m['media_url'] as String, mine: mine)
            else if (isFile)
              InkWell(onTap: () => launchMediaUrl(m['media_url'] as String), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.insert_drive_file, color: purple), const SizedBox(width: 8), Flexible(child: Text(m['body'] ?? 'Document', style: TextStyle(color: textColor)))]))
            else if (isVideo)
              InkWell(onTap: () => launchMediaUrl(m['media_url'] as String), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.play_circle_fill, color: Colors.white, size: 32), const SizedBox(width: 8), Text('Video • Tap to open', style: TextStyle(color: textColor))]))
            else if (isImage)
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


class ViewOnceViewer extends StatelessWidget {
  const ViewOnceViewer({super.key, required this.message});
  final Map<String, dynamic> message;
  @override Widget build(BuildContext context) {
    final url = message['media_url'] as String?;
    final kind = message['kind'] as String? ?? 'text';
    Widget content;
    if (kind == 'image' && url != null) {
      content = Image.network(url, fit: BoxFit.contain);
    } else if (kind == 'audio' && url != null) {
      content = _AudioMessage(url: url, mine: true);
    } else if ((kind == 'video' || kind == 'file') && url != null) {
      content = FilledButton.icon(onPressed: () => launchMediaUrl(url), icon: Icon(kind == 'video' ? Icons.play_arrow : Icons.download), label: Text(kind == 'video' ? 'Open video' : (message['body'] ?? 'Open attachment')));
    } else {
      content = Padding(padding: const EdgeInsets.all(24), child: Text(message['body'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 22)));
    }
    return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('View once')), body: Center(child: content));
  }
}

class _AudioMessage extends StatefulWidget {
  const _AudioMessage({required this.url, required this.mine});
  final String url; final bool mine;
  @override State<_AudioMessage> createState() => _AudioMessageState();
}
class _AudioMessageState extends State<_AudioMessage> {
  final player = AudioPlayer(); bool playing = false;
  @override void dispose() { player.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: () async { if (playing) { await player.pause(); } else { await player.play(UrlSource(widget.url)); } if (mounted) setState(() => playing = !playing); }, icon: Icon(playing ? Icons.pause_circle : Icons.play_circle, color: widget.mine ? Colors.white : purple, size: 30)), Text('Voice message', style: TextStyle(color: widget.mine ? Colors.white : ink))]);
}

Future<void> launchMediaUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
