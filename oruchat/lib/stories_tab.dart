import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'advanced_features.dart';

import 'config.dart';
import 'utils.dart';

bool _isActive(Map<String, dynamic> s) {
  final d = DateTime.tryParse((s['created_at'] ?? '') as String);
  if (d == null) return false;
  return d.isAfter(DateTime.now().toUtc().subtract(const Duration(hours: 24)));
}

class StoriesTab extends StatefulWidget {
  const StoriesTab({super.key});

  @override
  State<StoriesTab> createState() => _StoriesTabState();
}

class _StoriesTabState extends State<StoriesTab> {
  late final Stream<List<Map<String, dynamic>>> stream = sb
      .from('stories')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);
  bool busy = false;

  Future<void> addStory() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: purple),
              title: const Text('Photo from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: purple),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded, color: purple),
              title: const Text('Text story'),
              onTap: () => Navigator.pop(ctx, 'text'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'text') {
        final text = await askText(
          context,
          title: 'Text story',
          hint: 'What\'s on your mind?',
          multiline: true,
        );
        if (text == null || text.isEmpty) return;
        setState(() => busy = true);
        await sb.from('stories').insert({
          'user_id': myId,
          'kind': 'text',
          'caption': text,
        });
      } else {
        final source = choice == 'camera'
            ? ImageSource.camera
            : ImageSource.gallery;
        setState(() => busy = true);
        final picked = await ImagePicker().pickImage(source: source, imageQuality: 95);
        if (picked == null) return;
        if (!mounted) return;
        final original = await picked.readAsBytes();
        final filtered = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => StoryFilterPage(bytes: original)));
        if (filtered == null) return;
        final path = '$myId/${DateTime.now().microsecondsSinceEpoch}_story.jpg';
        await sb.storage.from('media').uploadBinary(path, filtered, fileOptions: const FileOptions(contentType: 'image/jpeg'));
        final url = sb.storage.from('media').getPublicUrl(path);
        if (!mounted) return;
        final caption = await askText(
          context,
          title: 'Add a caption (optional)',
          hint: 'Caption',
        );
        await sb.from('stories').insert({
          'user_id': myId,
          'kind': 'image',
          'media_url': url,
          'caption': (caption == null || caption.isEmpty) ? null : caption,
        });
      }
      if (mounted) snack(context, 'Story posted');
    } catch (e) {
      if (mounted) snack(context, 'Could not post story: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void openViewer(
    List<Map<String, dynamic>> stories,
    Map<String, dynamic> profile,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryViewerPage(stories: stories, profile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());

        final active = snap.data!.where(_isActive).toList();
        active.sort(
          (a, b) =>
              (a['created_at'] as String).compareTo(b['created_at'] as String),
        );
        final byUser = <String, List<Map<String, dynamic>>>{};
        for (final s in active) {
          byUser.putIfAbsent(s['user_id'] as String, () => []).add(s);
        }
        final mine = byUser.remove(myId) ?? [];
        final others = byUser.entries.toList()
          ..sort(
            (a, b) => (b.value.last['created_at'] as String).compareTo(
              a.value.last['created_at'] as String,
            ),
          );

        final me = ProfileCache.peek(myId);

        return ListView(
          children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            ListTile(
              leading: Stack(
                children: [
                  Avatar(
                    name: (me?['display_name'] ?? 'Me') as String,
                    url: me?['avatar_url'] as String?,
                    radius: 26,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: purple,
                      child: const Icon(
                        Icons.add,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              title: const Text(
                'My story',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                mine.isEmpty
                    ? 'Tap to add a story'
                    : '${mine.length} update(s) • ${fmtTime(mine.last['created_at'] as String?)}',
              ),
              onTap: mine.isEmpty
                  ? addStory
                  : () => openViewer(
                      mine,
                      me ?? {'id': myId, 'display_name': 'Me'},
                    ),
              trailing: IconButton(
                icon: const Icon(Icons.add_circle_outline, color: purple),
                onPressed: busy ? null : addStory,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Recent updates',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            ),
            if (others.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No stories from others right now.')),
              ),
            for (final entry in others)
              FutureBuilder<Map<String, dynamic>>(
                future: ProfileCache.get(entry.key),
                initialData: ProfileCache.peek(entry.key),
                builder: (context, ps) {
                  final p = ps.data ?? {'id': entry.key, 'display_name': '...'};
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: purple, width: 2.5),
                        ),
                      ),
                      child: Avatar(
                        name: (p['display_name'] ?? '?') as String,
                        url: p['avatar_url'] as String?,
                        radius: 23,
                      ),
                    ),
                    title: Text(
                      (p['display_name'] ?? '') as String,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      fmtDayTime(entry.value.last['created_at'] as String?),
                    ),
                    onTap: () => openViewer(entry.value, p),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class StoryViewerPage extends StatefulWidget {
  const StoryViewerPage({
    super.key,
    required this.stories,
    required this.profile,
  });

  final List<Map<String, dynamic>> stories;
  final Map<String, dynamic> profile;

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> {
  static const int storyMs = 5000;
  int index = 0;
  double progress = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    timer?.cancel();
    progress = 0;
    timer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) return;
      setState(() => progress += 50 / storyMs);
      if (progress >= 1) _next();
    });
  }

  void _next() {
    if (index < widget.stories.length - 1) {
      setState(() => index++);
      _startTimer();
    } else {
      timer?.cancel();
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (index > 0) {
      setState(() => index--);
    }
    _startTimer();
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    timer?.cancel();
    try {
      await sb.from('stories').delete().eq('id', s['id']);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        snack(context, 'Could not delete: $e');
        _startTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stories[index];
    final isText = s['kind'] == 'text' || s['media_url'] == null;
    final mine = s['user_id'] == myId;
    final name = (widget.profile['display_name'] ?? '') as String;
    final caption = s['caption'] as String?;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.localPosition.dx < w / 3) {
            _prev();
          } else {
            _next();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: isText
                  ? Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [purple, purpleDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: Text(
                        caption ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : Image.network(
                      s['media_url'] as String,
                      fit: BoxFit.contain,
                      loadingBuilder: (c, child, p) => p == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (c, e, st) => const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        for (int i = 0; i < widget.stories.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: LinearProgressIndicator(
                                value: i < index
                                    ? 1
                                    : (i == index
                                          ? progress.clamp(0.0, 1.0)
                                          : 0),
                                minHeight: 3,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: Avatar(
                      name: name,
                      url: widget.profile['avatar_url'] as String?,
                      radius: 18,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      fmtDayTime(s['created_at'] as String?),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mine)
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                            onPressed: () => _delete(s),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (!isText && caption != null && caption.isNotEmpty)
                    Container(
                      width: double.infinity,
                      color: Colors.black54,
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
