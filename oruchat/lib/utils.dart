import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

const Color purple = Color(0xFF6500E8);
const Color purpleDark = Color(0xFF3F00A8);
const Color lavender = Color(0xFFF2EAFE);
const Color pageBg = Color(0xFFF8F7FB);
const Color ink = Color(0xFF171326);

String chatIdFor(String a, String b) {
  final l = [a, b]..sort();
  return '${l[0]}_${l[1]}';
}

String groupChatId(String groupId) => 'g_$groupId';

String fmtTime(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String fmtDayTime(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return fmtTime(iso);
  if (diff == 1) return 'Yesterday';
  return '${d.day}/${d.month}/${d.year}';
}

String fmtDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

String fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// "online" / "last seen today at 5:20 PM" / ''
String presenceText(Map<String, dynamic> p) {
  if (p['online'] == true) return 'online';
  final iso = p['last_seen'] as String?;
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  final t = fmtTime(iso);
  if (diff == 0) return 'last seen today at $t';
  if (diff == 1) return 'last seen yesterday at $t';
  return 'last seen ${d.day}/${d.month}/${d.year}';
}

String previewOf(Map<String, dynamic> m) {
  if (m['once'] == true) return '🔒 One-time message';
  switch (m['kind']) {
    case 'image':
      return '📷 Photo';
    case 'video':
      return '🎥 Video';
    case 'voice':
      return '🎤 Voice message';
    case 'audio':
      return '🎵 Audio';
    case 'file':
      final meta = m['meta'];
      final name = meta is Map ? (meta['name'] ?? 'Document') : 'Document';
      return '📄 $name';
    case 'location':
      return '📍 Location';
    case 'sticker':
      return '${m['body'] ?? ''} Sticker';
    default:
      return (m['body'] ?? '') as String;
  }
}

void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String errText(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  return e.toString();
}

Future<void> openUrl(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) snack(context, 'Could not open the link.');
  } catch (_) {
    if (context.mounted) snack(context, 'Could not open the link.');
  }
}

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.url,
    this.radius = 24,
    this.icon,
  });

  final String name;
  final String? url;
  final double radius;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    final trimmed = name.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: lavender,
      backgroundImage: hasUrl ? NetworkImage(url!) : null,
      child: hasUrl
          ? null
          : (icon != null
                ? Icon(icon, color: purple, size: radius)
                : Text(
                    trimmed.isEmpty
                        ? '?'
                        : String.fromCharCode(trimmed.runes.first)
                              .toUpperCase(),
                    style: TextStyle(
                      color: purple,
                      fontWeight: FontWeight.w800,
                      fontSize: radius * 0.8,
                    ),
                  )),
    );
  }
}

/// Profiles Supabase `get_profiles()` function vazhi varunnu (privacy settings anusarichu).
class ProfileCache {
  static final Map<String, Map<String, dynamic>> _cache = {};

  static Map<String, dynamic>? peek(String id) => _cache[id];

  static void invalidate(String id) => _cache.remove(id);

  static void clearAll() => _cache.clear();

  static Map<String, dynamic> _fallback(String id) => {
    'id': id,
    'display_name': 'Unknown',
    'username': '',
    'avatar_url': null,
    'friend_status': 'none',
    'blocked_by_me': false,
    'blocked_me': false,
  };

  static Future<Map<String, dynamic>> get(
    String id, {
    bool fresh = false,
  }) async {
    final c = _cache[id];
    if (c != null && !fresh) return c;
    final res = await getMany([id]);
    return res[id] ?? _cache[id] ?? _fallback(id);
  }

  static Future<Map<String, Map<String, dynamic>>> getMany(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    try {
      final res = await sb.rpc('get_profiles', params: {'ids': ids});
      if (res is List) {
        for (final r in res) {
          final m = Map<String, dynamic>.from(r as Map);
          _cache[m['id'] as String] = m;
        }
      }
    } catch (_) {}
    return {
      for (final i in ids)
        if (_cache[i] != null) i: _cache[i]!,
    };
  }
}

/// "Clear chat" ethra mani muthal ennu orkkunnu (ente phone-il mathram).
class ClearCache {
  static final Map<String, DateTime> _m = {};

  static DateTime? at(String chatId) => _m[chatId];

  static Future<void> load() async {
    try {
      final rows = await sb.from('chat_clears').select().eq('user_id', myId);
      _m.clear();
      for (final r in rows) {
        final d = DateTime.tryParse((r['cleared_at'] ?? '') as String);
        if (d != null) _m[r['chat_id'] as String] = d;
      }
    } catch (_) {}
  }

  static Future<void> clear(String chatId) async {
    final now = DateTime.now().toUtc();
    await sb.from('chat_clears').upsert({
      'user_id': myId,
      'chat_id': chatId,
      'cleared_at': now.toIso8601String(),
    });
    _m[chatId] = now;
  }
}

bool messageVisible(Map<String, dynamic> m, {DateTime? clearedAt}) {
  final created = DateTime.tryParse((m['created_at'] ?? '') as String);
  if (created == null) return false;
  if (clearedAt != null && !created.isAfter(clearedAt)) return false;
  final exp = m['expires_at'];
  if (exp is String) {
    final e = DateTime.tryParse(exp);
    if (e != null && e.isBefore(DateTime.now().toUtc())) return false;
  }
  return true;
}

// ---------------- Friends / block actions ----------------

class Social {
  static Future<void> sendRequest(String peerId) async {
    await sb.from('friendships').insert({
      'requester_id': myId,
      'addressee_id': peerId,
      'status': 'pending',
    });
    ProfileCache.invalidate(peerId);
  }

  static Future<void> accept(String peerId) async {
    await sb
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('requester_id', peerId)
        .eq('addressee_id', myId);
    ProfileCache.invalidate(peerId);
  }

  /// Decline / cancel / unfriend ellaam ithu thanne.
  static Future<void> remove(String peerId) async {
    await sb
        .from('friendships')
        .delete()
        .or(
          'and(requester_id.eq.$myId,addressee_id.eq.$peerId),and(requester_id.eq.$peerId,addressee_id.eq.$myId)',
        );
    ProfileCache.invalidate(peerId);
  }

  static Future<void> block(String peerId) async {
    await sb.from('blocks').upsert({'blocker_id': myId, 'blocked_id': peerId});
    try {
      await remove(peerId);
    } catch (_) {}
    ProfileCache.invalidate(peerId);
  }

  static Future<void> unblock(String peerId) async {
    await sb
        .from('blocks')
        .delete()
        .eq('blocker_id', myId)
        .eq('blocked_id', peerId);
    ProfileCache.invalidate(peerId);
  }

  static Future<List<String>> friendIds() async {
    final rows = await sb.from('friendships').select().eq('status', 'accepted');
    final out = <String>[];
    for (final r in rows) {
      final a = r['requester_id'] as String;
      final b = r['addressee_id'] as String;
      out.add(a == myId ? b : a);
    }
    return out;
  }
}

// ---------------- Upload / pick helpers ----------------

String contentTypeFor(String ext) {
  switch (ext.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'mkv':
      return 'video/x-matroska';
    case 'm4a':
      return 'audio/mp4';
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'aac':
      return 'audio/aac';
    case 'ogg':
      return 'audio/ogg';
    case 'pdf':
      return 'application/pdf';
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
}

Future<String> uploadBytes(
  Uint8List bytes,
  String ext, {
  String? contentType,
}) async {
  final cleanExt = ext.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
  final e = cleanExt.isEmpty ? 'bin' : cleanExt;
  final path = '$myId/${DateTime.now().microsecondsSinceEpoch}.$e';
  await sb.storage
      .from('media')
      .uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType ?? contentTypeFor(e)),
      );
  return sb.storage.from('media').getPublicUrl(path);
}

Future<Uint8List?> pickImageBytes(ImageSource source) async {
  final picker = ImagePicker();
  final x = await picker.pickImage(
    source: source,
    maxWidth: 1280,
    imageQuality: 85,
  );
  if (x == null) return null;
  return x.readAsBytes();
}

Future<ImageSource?> chooseImageSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: purple),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded, color: purple),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
}

/// Profile photo-kku: photo edukkum, upload cheyyum, URL tharum.
Future<String?> pickAndUploadImage(ImageSource source) async {
  final bytes = await pickImageBytes(source);
  if (bytes == null) return null;
  return uploadBytes(bytes, 'jpg', contentType: 'image/jpeg');
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
  bool multiline = false,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: multiline ? 5 : 1,
        minLines: multiline ? 3 : 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context,
  String title, {
  String? message,
  String okLabel = 'OK',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel),
        ),
      ],
    ),
  );
  return r == true;
}

class ImageViewPage extends StatelessWidget {
  const ImageViewPage({super.key, required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(child: InteractiveViewer(child: Image.network(url))),
    );
  }
}
