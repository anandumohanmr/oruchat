import 'package:flutter/material.dart';

import 'call_service.dart';
import 'config.dart';
import 'utils.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  late final Stream<List<Map<String, dynamic>>> stream = sb
      .from('call_logs')
      .stream(primaryKey: ['id'])
      .eq('user_id', myId)
      .order('created_at', ascending: false);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final logs = [...snap.data!];
        logs.sort(
          (a, b) =>
              (b['created_at'] as String).compareTo(a['created_at'] as String),
        );
        if (logs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No calls yet.\nOpen a chat and tap the phone or video icon to call.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: logs.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, i) {
            final l = logs[i];
            final peerId = l['peer_id'] as String;
            final outgoing = l['direction'] == 'outgoing';
            final status = l['status'] as String? ?? '';
            final bad =
                status == 'missed' ||
                status == 'rejected' ||
                status == 'unanswered';
            final dur = (l['duration_s'] ?? 0) as int;
            final isVideo = l['video'] == true;
            return FutureBuilder<Map<String, dynamic>>(
              future: ProfileCache.get(peerId),
              initialData: ProfileCache.peek(peerId),
              builder: (context, ps) {
                final p = ps.data ?? {'id': peerId, 'display_name': '...'};
                final label = status == 'completed'
                    ? (dur > 0 ? fmtDuration(dur) : 'Completed')
                    : status[0].toUpperCase() + status.substring(1);
                return ListTile(
                  leading: Avatar(
                    name: (p['display_name'] ?? '?') as String,
                    url: p['avatar_url'] as String?,
                    radius: 24,
                  ),
                  title: Text(
                    (p['display_name'] ?? '') as String,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Row(
                    children: [
                      Icon(
                        outgoing
                            ? Icons.call_made_rounded
                            : Icons.call_received_rounded,
                        size: 15,
                        color: bad && !outgoing ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${fmtDayTime(l['created_at'] as String?)} • $label',
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: purple,
                    ),
                    onPressed: () => CallService.instance.startCall(
                      context,
                      p,
                      video: isVideo,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
