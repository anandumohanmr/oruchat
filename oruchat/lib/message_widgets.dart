import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'config.dart';
import 'utils.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.m,
    required this.isGroup,
    required this.onOpenOnce,
  });

  final Map<String, dynamic> m;
  final bool isGroup;
  final void Function(Map<String, dynamic> m) onOpenOnce;

  Map<String, dynamic> get meta {
    final x = m['meta'];
    return x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final mine = m['sender_id'] == myId;
    final kind = (m['kind'] ?? 'text') as String;
    final once = m['once'] == true;
    final read = m['read_at'] != null;
    final hasExpiry = m['expires_at'] != null;
    final textColor = mine ? Colors.white : ink;
    final subColor = mine ? Colors.white70 : Colors.black45;

    // ---- sticker: bubble illathe ----
    if (kind == 'sticker' && !once) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (isGroup && !mine) _SenderName(id: m['sender_id'] as String),
              Text(
                (m['body'] ?? '') as String,
                style: const TextStyle(fontSize: 76),
              ),
              Text(
                fmtTime(m['created_at'] as String?),
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
      );
    }

    final Widget content;
    var tightPadding = false;

    if (once) {
      final opened = m['viewed_at'] != null;
      final label = kind == 'image'
          ? 'Photo'
          : kind == 'video'
          ? 'Video'
          : 'Message';
      if (mine) {
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_1_rounded, size: 18, color: textColor),
            const SizedBox(width: 8),
            Text(
              opened ? 'One-time $label · Opened' : 'One-time $label · Sent',
              style: TextStyle(color: textColor, fontSize: 15),
            ),
          ],
        );
      } else if (opened) {
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: Colors.black45),
            SizedBox(width: 8),
            Text(
              'Opened',
              style: TextStyle(color: Colors.black54, fontSize: 15),
            ),
          ],
        );
      } else {
        content = InkWell(
          onTap: () => onOpenOnce(m),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_1_rounded, size: 20, color: purple),
              const SizedBox(width: 8),
              Text(
                'One-time $label · Tap to open',
                style: const TextStyle(
                  color: purple,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        );
      }
    } else {
      switch (kind) {
        case 'image':
          tightPadding = true;
          final imgUrl = m['media_url'] as String?;
          final imgCap = (m['body'] ?? '') as String;
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imgUrl != null)
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ImageViewPage(url: imgUrl),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imgUrl,
                      width: 230,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, child, p) => p == null
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
                ),
              if (imgCap.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Text(
                    imgCap,
                    style: TextStyle(color: textColor, fontSize: 16),
                  ),
                ),
            ],
          );
          break;
        case 'video':
          tightPadding = true;
          final vidUrl = m['media_url'] as String?;
          final vidCap = (m['body'] ?? '') as String;
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: vidUrl == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoPage(url: vidUrl),
                        ),
                      ),
                child: Container(
                  width: 230,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),
              ),
              if (vidCap.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Text(
                    vidCap,
                    style: TextStyle(color: textColor, fontSize: 16),
                  ),
                ),
            ],
          );
          break;
        case 'voice':
        case 'audio':
          final audUrl = m['media_url'] as String?;
          final secs = (meta['seconds'] is num)
              ? (meta['seconds'] as num).toInt()
              : null;
          content = audUrl == null
              ? Text('Audio unavailable', style: TextStyle(color: textColor))
              : AudioBubble(
                  url: audUrl,
                  mine: mine,
                  seconds: secs,
                  title: kind == 'audio'
                      ? (meta['name'] ?? 'Audio') as String
                      : null,
                );
          break;
        case 'file':
          final fileUrl = m['media_url'] as String?;
          final name = (meta['name'] ?? m['body'] ?? 'Document') as String;
          final size = (meta['size'] is num)
              ? (meta['size'] as num).toInt()
              : null;
          content = InkWell(
            onTap: fileUrl == null ? null : () => openUrl(context, fileUrl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insert_drive_file_rounded,
                  color: mine ? Colors.white : purple,
                  size: 34,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (size != null)
                        Text(
                          fmtSize(size),
                          style: TextStyle(color: subColor, fontSize: 12),
                        ),
                      Text(
                        'Tap to open',
                        style: TextStyle(color: subColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
          break;
        case 'location':
          final parts = ((m['body'] ?? '') as String).split(',');
          final lat = parts.isNotEmpty ? parts[0].trim() : '';
          final lng = parts.length > 1 ? parts[1].trim() : '';
          content = InkWell(
            onTap: () => openUrl(
              context,
              'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      color: mine ? Colors.white : Colors.redAccent,
                      size: 30,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Location',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$lat, $lng',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Open in Maps',
                  style: TextStyle(
                    color: mine ? Colors.white : purple,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
          break;
        case 'sticker':
          content = Text(
            (m['body'] ?? '') as String,
            style: const TextStyle(fontSize: 64),
          );
          break;
        default:
          content = Text(
            (m['body'] ?? '') as String,
            style: TextStyle(color: textColor, fontSize: 16),
          );
      }
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: tightPadding
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
            if (isGroup && !mine)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: tightPadding
                      ? const EdgeInsets.fromLTRB(6, 2, 6, 4)
                      : EdgeInsets.zero,
                  child: _SenderName(id: m['sender_id'] as String),
                ),
              ),
            Align(alignment: Alignment.centerLeft, child: content),
            const SizedBox(height: 2),
            Padding(
              padding: tightPadding
                  ? const EdgeInsets.fromLTRB(0, 0, 6, 2)
                  : EdgeInsets.zero,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasExpiry)
                    Icon(Icons.timer_outlined, size: 12, color: subColor),
                  if (hasExpiry) const SizedBox(width: 3),
                  Text(
                    fmtTime(m['created_at'] as String?),
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                  if (mine && !isGroup) ...[
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

class _SenderName extends StatelessWidget {
  const _SenderName({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ProfileCache.get(id),
      initialData: ProfileCache.peek(id),
      builder: (context, snap) {
        final name = (snap.data?['display_name'] ?? '...') as String;
        return Text(
          name,
          style: const TextStyle(
            color: purple,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        );
      },
    );
  }
}

class AudioBubble extends StatefulWidget {
  const AudioBubble({
    super.key,
    required this.url,
    required this.mine,
    this.seconds,
    this.title,
  });

  final String url;
  final bool mine;
  final int? seconds;
  final String? title;

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final AudioPlayer player = AudioPlayer();
  bool playing = false;
  bool started = false;
  Duration pos = Duration.zero;
  Duration? dur;
  final List<StreamSubscription<dynamic>> subs = [];

  @override
  void initState() {
    super.initState();
    subs.add(
      player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => playing = s == PlayerState.playing);
      }),
    );
    subs.add(
      player.onPositionChanged.listen((d) {
        if (mounted) setState(() => pos = d);
      }),
    );
    subs.add(
      player.onDurationChanged.listen((d) {
        if (mounted) setState(() => dur = d);
      }),
    );
    subs.add(
      player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            playing = false;
            started = false;
            pos = Duration.zero;
          });
        }
      }),
    );
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (playing) {
        await player.pause();
      } else if (started) {
        await player.resume();
      } else {
        started = true;
        await player.play(UrlSource(widget.url));
      }
    } catch (_) {
      if (mounted) snack(context, 'Could not play this audio.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine ? Colors.white : purple;
    final total = dur?.inSeconds ?? widget.seconds ?? 0;
    final value = (dur != null && dur!.inMilliseconds > 0)
        ? (pos.inMilliseconds / dur!.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(
              playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: fg,
              size: 38,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.title != null)
                  Text(
                    widget.title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  color: fg,
                  backgroundColor: fg.withOpacity(0.25),
                ),
                const SizedBox(height: 4),
                Text(
                  '${fmtDuration(pos.inSeconds)} / ${fmtDuration(total)}',
                  style: TextStyle(
                    color: widget.mine ? Colors.white70 : Colors.black54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.url});
  final String url;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  late final VideoPlayerController c;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    c.addListener(() {
      if (mounted) setState(() {});
    });
    c
        .initialize()
        .then((_) {
          if (mounted) {
            setState(() {});
            c.play();
          }
        })
        .catchError((_) {
          if (mounted) setState(() => failed = true);
        });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: failed
                  ? const Text(
                      'Could not play this video',
                      style: TextStyle(color: Colors.white),
                    )
                  : c.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          if (c.value.isInitialized)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => c.value.isPlaying ? c.pause() : c.play(),
                      icon: Icon(
                        c.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        c,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: purple,
                          bufferedColor: Colors.white30,
                          backgroundColor: Colors.white12,
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
