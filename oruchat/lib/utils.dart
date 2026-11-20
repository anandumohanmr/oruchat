import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.url, this.radius = 24});

  final String name;
  final String? url;
  final double radius;

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
          : Text(
              trimmed.isEmpty
                  ? '?'
                  : String.fromCharCode(trimmed.runes.first).toUpperCase(),
              style: TextStyle(
                color: purple,
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.8,
              ),
            ),
    );
  }
}

class ProfileCache {
  static final Map<String, Map<String, dynamic>> _cache = {};

  static Map<String, dynamic>? peek(String id) => _cache[id];

  static void invalidate(String id) => _cache.remove(id);

  static Future<Map<String, dynamic>> get(String id) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    try {
      final row = await sb.from('profiles').select().eq('id', id).maybeSingle();
      if (row != null) {
        _cache[id] = row;
        return row;
      }
    } catch (_) {}
    return {
      'id': id,
      'display_name': 'Unknown',
      'username': '',
      'avatar_url': null,
    };
  }
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

/// Photo edukkum, Supabase storage-il upload cheyyum, public URL tharum.
Future<String?> pickAndUploadImage(ImageSource source) async {
  final picker = ImagePicker();
  final x = await picker.pickImage(
    source: source,
    maxWidth: 1280,
    imageQuality: 80,
  );
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  final path = '$myId/${DateTime.now().microsecondsSinceEpoch}.jpg';
  await sb.storage
      .from('media')
      .uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
  return sb.storage.from('media').getPublicUrl(path);
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
