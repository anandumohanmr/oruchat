import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'call_service.dart';
import 'config.dart';
import 'filters.dart';
import 'group_pages.dart';
import 'lock_service.dart';
import 'message_widgets.dart';
import 'utils.dart';

const int kMaxUploadBytes = 48 * 1024 * 1024;

const List<String> kStickers = [
  '😀',
  '😂',
  '🥰',
  '😍',
  '😎',
  '🤩',
  '😭',
  '😡',
  '🥳',
  '😴',
  '🤔',
  '🙏',
  '👍',
  '👏',
  '🔥',
  '💯',
  '❤️',
  '💜',
  '🎉',
  '🎂',
  '🌹',
  '☕',
  '🍕',
  '🍔',
  '🏏',
  '⚽',
  '🎵',
  '📸',
  '✈️',
  '🏖️',
  '🌴',
  '🐶',
  '🐱',
  '🦁',
  '🐼',
  '🐵',
  '🌈',
  '⭐',
  '🌙',
  '☀️',
  '🚗',
  '🏍️',
  '🎁',
  '💐',
  '🙌',
  '🤝',
  '💪',
  '😘',
];

const Map<String, int> kDisappearOptions = {
  'Off': 0,
  '1 minute': 60,
  '1 hour': 3600,
  '24 hours': 86400,
  '1 month': 2592000,
};

String disappearLabel(int seconds) {
  for (final e in kDisappearOptions.entries) {
    if (e.value == seconds) return e.key;
  }
  return 'Off';
}

/// Chat thurakkaan (locked aanenkil PIN chodikkum).
Future<void> openChat(
  BuildContext context, {
  Map<String, dynamic>? peer,
  Map<String, dynamic>? group,
}) async {
  final cid = group != null
      ? groupChatId(group['id'] as String)
      : chatIdFor(myId, peer!['id'] as String);
  if (LockService.instance.isLocked(cid)) {
    final ok = await askPin(context);
    if (!ok || !context.mounted) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatPage(peer: peer, group: group),
    ),
  );
}

/// Search result-il ninnu chat thurakkaan.
Future<void> openChatForMessage(
  BuildContext context,
  Map<String, dynamic> m,
) async {
  if (m['group_id'] != null) {
    final g = await GroupCache.get(m['group_id'] as String);
    if (context.mounted) await openChat(context, group: g);
  } else {
    final other =
        (m['sender_id'] == myId ? m['receiver_id'] : m['sender_id']) as String;
    final p = await ProfileCache.get(other);
    if (context.mounted) await openChat(context, peer: p);
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.peer, this.group})
    : assert(peer != null || group != null);

  final Map<String, dynamic>? peer;
  final Map<String, dynamic>? group;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late Map<String, dynamic>? peer = widget.peer;
  late Map<String, dynamic>? group = widget.group;

  bool get isGroup => group != null;
  String get peerId => peer!['id'] as String;
  String get title => isGroup
      ? (group!['name'] ?? 'Group') as String
      : (peer!['display_name'] ?? '') as String;
  String? get avatarUrl => isGroup
      ? group!['avatar_url'] as String?
      : peer!['avatar_url'] as String?;

  late final String chatId = isGroup
      ? groupChatId(group!['id'] as String)
      : chatIdFor(myId, peer!['id'] as String);

  late final Stream<List<Map<String, dynamic>>> msgStream = sb
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('chat_id', chatId)
      .order('created_at', ascending: false);
  late final Stream<List<Map<String, dynamic>>> settingsStream = sb
      .from('chat_settings')
      .stream(primaryKey: ['chat_id'])
      .eq('chat_id', chatId);

  final input = TextEditingController();
  final searchCtl = TextEditingController();
  final AudioRecorder _rec = AudioRecorder();

  bool marking = false;
  bool uploading = false;
  bool onceMode = false;
  bool searchMode = false;
  bool recording = false;
  int recSeconds = 0;
  Timer? recTimer;
  Timer? tick;
  int tickCount = 0;
  DateTime? clearedAt;

  @override
  void initState() {
    super.initState();
    clearedAt = ClearCache.at(chatId);
    _refreshPeer();
    tick = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      tickCount++;
      if (tickCount % 3 == 0) _refreshPeer();
      setState(() {});
    });
  }

  @override
  void dispose() {
    tick?.cancel();
    recTimer?.cancel();
    _rec.dispose();
    input.dispose();
    searchCtl.dispose();
    super.dispose();
  }

  Future<void> _refreshPeer() async {
    if (isGroup) return;
    final p = await ProfileCache.get(peerId, fresh: true);
    if (mounted) setState(() => peer = p);
  }

  // ---------------- sending ----------------

  Future<bool> _insert({
    String? body,
    String? mediaUrl,
    required String kind,
    Map<String, dynamic>? meta,
    bool once = false,
  }) async {
    final canOnce =
        !isGroup && (kind == 'text' || kind == 'image' || kind == 'video');
    try {
      await sb.from('messages').insert({
        'chat_id': chatId,
        'sender_id': myId,
        if (isGroup) 'group_id': group!['id'] else 'receiver_id': peerId,
        'body': body,
        'media_url': mediaUrl,
        'kind': kind,
        'meta': meta ?? <String, dynamic>{},
        'once': once && canOnce,
      });
      if (once && mounted) setState(() => onceMode = false);
      return true;
    } on PostgrestException catch (e) {
      if (mounted) {
        snack(
          context,
          e.code == '42501'
              ? 'Message not sent. This person accepts messages only from friends.'
              : 'Message not sent: ${e.message}',
        );
      }
      return false;
    } catch (e) {
      if (mounted) snack(context, 'Message not sent: $e');
      return false;
    }
  }

  Future<void> _busy(Future<void> Function() job) async {
    if (!mounted) return;
    setState(() => uploading = true);
    try {
      await job();
    } catch (e) {
      if (mounted) snack(context, 'Failed: ${errText(e)}');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> sendText() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    await _insert(body: text, kind: 'text', once: onceMode);
  }

  Future<void> _sendPhoto(ImageSource source) async {
    final bytes = await pickImageBytes(source);
    if (bytes == null || !mounted) return;
    final r = await editImage(context, bytes);
    if (r == null) return;
    await _busy(() async {
      final url = await uploadBytes(
        r.bytes,
        r.isPng ? 'png' : 'jpg',
        contentType: r.isPng ? 'image/png' : 'image/jpeg',
      );
      await _insert(
        kind: 'image',
        mediaUrl: url,
        body: r.caption,
        once: onceMode,
      );
    });
  }

  Future<void> _sendVideo() async {
    final src = await chooseImageSource(context);
    if (src == null) return;
    final x = await ImagePicker().pickVideo(
      source: src,
      maxDuration: const Duration(minutes: 5),
    );
    if (x == null || !mounted) return;
    final size = await x.length();
    if (size > kMaxUploadBytes) {
      if (mounted) snack(context, 'Video is too big (max 48 MB).');
      return;
    }
    await _busy(() async {
      final bytes = await x.readAsBytes();
      final ext = x.name.contains('.') ? x.name.split('.').last : 'mp4';
      final url = await uploadBytes(
        bytes,
        ext,
        contentType: contentTypeFor(ext),
      );
      await _insert(
        kind: 'video',
        mediaUrl: url,
        meta: {'name': x.name, 'size': size},
        once: onceMode,
      );
    });
  }

  Future<void> _sendFile({required bool audio}) async {
    final res = await FilePicker.platform.pickFiles(
      type: audio ? FileType.audio : FileType.any,
      allowMultiple: false,
    );
    if (res == null || res.files.isEmpty || !mounted) return;
    final f = res.files.single;
    if (f.path == null) {
      snack(context, 'Could not read that file.');
      return;
    }
    if (f.size > kMaxUploadBytes) {
      snack(context, 'File is too big (max 48 MB).');
      return;
    }
    await _busy(() async {
      final bytes = await File(f.path!).readAsBytes();
      final ext =
          f.extension ??
          (f.name.contains('.') ? f.name.split('.').last : 'bin');
      final url = await uploadBytes(
        bytes,
        ext,
        contentType: contentTypeFor(ext),
      );
      await _insert(
        kind: audio ? 'audio' : 'file',
        mediaUrl: url,
        body: f.name,
        meta: {'name': f.name, 'size': f.size, 'ext': ext},
      );
    });
  }

  Future<void> _sendLocation() async {
    final ok = await confirmDialog(
      context,
      'Share your current location?',
      message: 'Only people in this chat will see it.',
      okLabel: 'Share',
    );
    if (!ok || !mounted) return;
    await _busy(() async {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) snack(context, 'Please turn on location (GPS).');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted)
          snack(
            context,
            'Location permission is needed to share your location.',
          );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      await _insert(
        kind: 'location',
        body:
            '${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)}',
      );
    });
  }

  Future<void> _sendSticker(String s) async {
    await _insert(kind: 'sticker', body: s);
  }

  // ---------------- voice ----------------

  Future<void> _startRecording() async {
    try {
      if (!await _rec.hasPermission()) {
        if (mounted)
          snack(context, 'Microphone permission is needed for voice messages.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/oruchat_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      recSeconds = 0;
      if (mounted) setState(() => recording = true);
      recTimer?.cancel();
      recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => recSeconds++);
        if (recSeconds >= 300) _stopRecording(send: true);
      });
    } catch (e) {
      if (mounted) snack(context, 'Could not start recording: $e');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    recTimer?.cancel();
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    final secs = recSeconds;
    if (mounted) setState(() => recording = false);
    if (path == null) return;
    final filePath = path;
    if (!send) {
      try {
        await File(filePath).delete();
      } catch (_) {}
      return;
    }
    if (secs < 1) {
      if (mounted) snack(context, 'Recording was too short.');
      return;
    }
    await _busy(() async {
      final bytes = await File(filePath).readAsBytes();
      final url = await uploadBytes(bytes, 'm4a', contentType: 'audio/mp4');
      await _insert(kind: 'voice', mediaUrl: url, meta: {'seconds': secs});
      try {
        await File(filePath).delete();
      } catch (_) {}
    });
  }

  // ---------------- one time ----------------

  Future<void> _openOnce(Map<String, dynamic> m) async {
    try {
      final res = await sb.rpc('open_once', params: {'mid': m['id']});
      if (res == null) {
        if (mounted) snack(context, 'This message was already opened.');
        return;
      }
      final r = Map<String, dynamic>.from(res as Map);
      if (!mounted) return;
      final kind = r['kind'];
      final url = r['media_url'] as String?;
      final body = r['body'] as String?;
      if (kind == 'image' && url != null) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ImageViewPage(url: url)));
      } else if (kind == 'video' && url != null) {
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => VideoPage(url: url)));
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('One-time message'),
            content: Text(body ?? ''),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  // ---------------- read receipts ----------------

  Future<void> markRead(List<Map<String, dynamic>> list) async {
    if (isGroup || marking) return;
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

  // ---------------- menu actions ----------------

  Future<void> _setDisappear() async {
    final current = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Disappearing messages'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'New messages in this chat will be deleted after the time you choose.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          for (final e in kDisappearOptions.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.value),
              child: Text(e.key, style: const TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
    if (current == null) return;
    try {
      await sb.from('chat_settings').upsert({
        'chat_id': chatId,
        'disappear_seconds': current,
        'updated_by': myId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        snack(
          context,
          current == 0
              ? 'Disappearing messages turned off'
              : 'Messages will disappear after ${disappearLabel(current)}',
        );
      }
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _toggleLock() async {
    final lock = LockService.instance;
    final locked = lock.isLocked(chatId);
    if (!locked) {
      if (!await ensurePinSet(context)) return;
      await lock.setLocked(chatId, true);
      if (mounted)
        snack(context, 'Chat locked. You will need your PIN to open it.');
    } else {
      if (!await askPin(context, title: 'Enter PIN to unlock')) return;
      await lock.setLocked(chatId, false);
      if (mounted) snack(context, 'Chat unlocked');
    }
    if (mounted) setState(() {});
  }

  Future<void> _clearChat() async {
    final ok = await confirmDialog(
      context,
      'Clear this chat?',
      message: 'Messages will be removed from your view. The other person keeps their copy.',
      okLabel: 'Clear',
    );
    if (!ok) return;
    try {
      await ClearCache.clear(chatId);
      if (mounted) setState(() => clearedAt = ClearCache.at(chatId));
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _toggleBlock() async {
    final blocked = peer!['blocked_by_me'] == true;
    if (!blocked) {
      final ok = await confirmDialog(
        context,
        'Block $title?',
        message: 'They will not be able to message or call you, and they will be removed from your friends.',
        okLabel: 'Block',
      );
      if (!ok) return;
    }
    try {
      if (blocked) {
        await Social.unblock(peerId);
      } else {
        await Social.block(peerId);
      }
      await _refreshPeer();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _friendAction() async {
    try {
      final st = peer!['friend_status'];
      if (st == 'none') {
        await Social.sendRequest(peerId);
        if (mounted) snack(context, 'Friend request sent');
      } else if (st == 'pending_in') {
        await Social.accept(peerId);
        if (mounted) snack(context, 'You are now friends');
      }
      await _refreshPeer();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  Future<void> _openGroupInfo() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GroupInfoPage(group: group!)));
    final g = await GroupCache.get(group!['id'] as String, fresh: true);
    if (mounted) setState(() => group = g);
  }

  void _call(bool video) {
    CallService.instance.startCall(context, peer!, video: video);
  }

  // ---------------- sheets ----------------

  void _showAttachSheet() {
    Widget item(IconData icon, String label, Color color, VoidCallback onTap) {
      return InkWell(
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 86,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color,
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 20,
            children: [
              item(
                Icons.photo_library_rounded,
                'Gallery',
                Colors.purple,
                () => _sendPhoto(ImageSource.gallery),
              ),
              item(
                Icons.photo_camera_rounded,
                'Camera',
                Colors.pink,
                () => _sendPhoto(ImageSource.camera),
              ),
              item(
                Icons.videocam_rounded,
                'Video',
                Colors.deepOrange,
                _sendVideo,
              ),
              item(
                Icons.insert_drive_file_rounded,
                'Document',
                Colors.indigo,
                () => _sendFile(audio: false),
              ),
              item(
                Icons.headphones_rounded,
                'Audio',
                Colors.teal,
                () => _sendFile(audio: true),
              ),
              item(
                Icons.location_on_rounded,
                'Location',
                Colors.green,
                _sendLocation,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStickerSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 300,
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
            ),
            itemCount: kStickers.length,
            itemBuilder: (context, i) => InkWell(
              onTap: () {
                Navigator.pop(ctx);
                _sendSticker(kStickers[i]);
              },
              child: Center(
                child: Text(kStickers[i], style: const TextStyle(fontSize: 34)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------- UI ----------------

  PreferredSizeWidget _appBar() {
    if (searchMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            searchMode = false;
            searchCtl.clear();
          }),
        ),
        title: TextField(
          controller: searchCtl,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Search in this chat',
            border: InputBorder.none,
          ),
        ),
      );
    }
    final locked = LockService.instance.isLocked(chatId);
    String sub = '';
    if (isGroup) {
      sub = 'Tap for group info';
    } else if (peer!['blocked_by_me'] == true) {
      sub = 'Blocked';
    } else {
      sub = presenceText(peer!);
      if (sub.isEmpty) sub = '@${peer!['username'] ?? ''}';
    }
    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        onTap: isGroup ? _openGroupInfo : null,
        child: Row(
          children: [
            Avatar(
              name: title,
              url: avatarUrl,
              radius: 19,
              icon: isGroup ? Icons.groups_rounded : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!isGroup)
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam_rounded, color: purple),
            onPressed: () => _call(true),
          ),
        if (!isGroup)
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.call_rounded, color: purple),
            onPressed: () => _call(false),
          ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'search':
                setState(() => searchMode = true);
                break;
              case 'disappear':
                _setDisappear();
                break;
              case 'lock':
                _toggleLock();
                break;
              case 'clear':
                _clearChat();
                break;
              case 'block':
                _toggleBlock();
                break;
              case 'info':
                _openGroupInfo();
                break;
            }
          },
          itemBuilder: (_) => [
            if (isGroup)
              const PopupMenuItem(value: 'info', child: Text('Group info')),
            const PopupMenuItem(value: 'search', child: Text('Search')),
            const PopupMenuItem(
              value: 'disappear',
              child: Text('Disappearing messages'),
            ),
            PopupMenuItem(
              value: 'lock',
              child: Text(locked ? 'Unlock chat' : 'Lock chat'),
            ),
            const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
            if (!isGroup)
              PopupMenuItem(
                value: 'block',
                child: Text(
                  peer!['blocked_by_me'] == true ? 'Unblock' : 'Block',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _friendBanner() {
    if (isGroup) return const SizedBox.shrink();
    final st = peer!['friend_status'];
    if (st == 'friends' || st == 'self' || peer!['blocked_by_me'] == true)
      return const SizedBox.shrink();
    String label;
    VoidCallback? action;
    if (st == 'pending_out') {
      label = 'Requested';
      action = null;
    } else if (st == 'pending_in') {
      label = 'Accept';
      action = _friendAction;
    } else {
      label = 'Add friend';
      action = _friendAction;
    }
    return Material(
      color: lavender,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: purple),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Not friends yet. Voice and video calls need a friend connection.',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
            TextButton(onPressed: action, child: Text(label)),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    if (!isGroup && peer!['blocked_by_me'] == true) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(child: Text('You blocked this contact.')),
              FilledButton(
                onPressed: _toggleBlock,
                style: FilledButton.styleFrom(backgroundColor: purple),
                child: const Text('Unblock'),
              ),
            ],
          ),
        ),
      );
    }
    if (recording) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                onPressed: () => _stopRecording(send: false),
              ),
              const Icon(
                Icons.fiber_manual_record,
                color: Colors.red,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text(
                'Recording  ${fmtDuration(recSeconds)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              CircleAvatar(
                backgroundColor: purple,
                child: IconButton(
                  onPressed: () => _stopRecording(send: true),
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
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: uploading ? null : _showAttachSheet,
              icon: const Icon(Icons.attach_file_rounded, color: purple),
            ),
            IconButton(
              onPressed: _showStickerSheet,
              icon: const Icon(Icons.emoji_emotions_outlined, color: purple),
            ),
            Expanded(
              child: TextField(
                controller: input,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: onceMode ? 'One-time message' : 'Message',
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
            if (!isGroup)
              IconButton(
                tooltip: 'One-time message',
                onPressed: () => setState(() => onceMode = !onceMode),
                icon: Icon(
                  Icons.filter_1_rounded,
                  color: onceMode ? purple : Colors.black38,
                ),
              ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: input,
              builder: (context, value, _) {
                final empty = value.text.trim().isEmpty;
                return CircleAvatar(
                  backgroundColor: purple,
                  child: IconButton(
                    onPressed: empty ? _startRecording : sendText,
                    icon: Icon(
                      empty ? Icons.mic_rounded : Icons.send_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
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
    final q = searchCtl.text.trim().toLowerCase();
    return Scaffold(
      appBar: _appBar(),
      body: Column(
        children: [
          _friendBanner(),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: settingsStream,
            builder: (context, snap) {
              final rows = snap.data ?? <Map<String, dynamic>>[];
              final secs = rows.isEmpty
                  ? 0
                  : (rows.first['disappear_seconds'] as num?)?.toInt() ?? 0;
              if (secs <= 0) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Colors.black.withOpacity(0.05),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Disappearing messages: ${disappearLabel(secs)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: msgStream,
              builder: (context, snap) {
                if (snap.hasError)
                  return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => markRead(snap.data!),
                );
                var list = snap.data!
                    .where((m) => messageVisible(m, clearedAt: clearedAt))
                    .toList();
                list.sort(
                  (a, b) => (b['created_at'] as String).compareTo(
                    a['created_at'] as String,
                  ),
                );
                if (q.isNotEmpty) {
                  list = list.where((m) {
                    if (m['once'] == true) return false;
                    final body = ((m['body'] ?? '') as String).toLowerCase();
                    final meta = m['meta'];
                    final name = meta is Map
                        ? ((meta['name'] ?? '') as String).toLowerCase()
                        : '';
                    return body.contains(q) || name.contains(q);
                  }).toList();
                }
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      q.isNotEmpty ? 'No messages found' : 'Say hi 👋',
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemCount: list.length,
                  itemBuilder: (context, i) => MessageBubble(
                    key: ValueKey(list[i]['id']),
                    m: list[i],
                    isGroup: isGroup,
                    onOpenOnce: _openOnce,
                  ),
                );
              },
            ),
          ),
          if (uploading) const LinearProgressIndicator(minHeight: 2),
          _composer(),
        ],
      ),
    );
  }
}
