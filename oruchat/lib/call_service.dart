import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide Navigator;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'call_page.dart';
import 'config.dart';
import 'utils.dart';

/// Oru call-inte ellaam (WebRTC connection, signaling, call log).
class CallSession {
  CallSession({
    required this.callId,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    required this.video,
    required this.isCaller,
    this.offer,
  });

  final String callId;
  final String peerId;
  final String peerName;
  final String? peerAvatar;
  final bool video;
  final bool isCaller;
  final Map<String, dynamic>? offer;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final ValueNotifier<String> status = ValueNotifier<String>('Calling…');
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);
  final ValueNotifier<bool> ended = ValueNotifier<bool>(false);
  final ValueNotifier<bool> muted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> camOff = ValueNotifier<bool>(false);
  late final ValueNotifier<bool> speaker = ValueNotifier<bool>(video);

  RTCPeerConnection? _pc;
  MediaStream? _local;
  final List<Map<String, dynamic>> _candidates = [];
  bool _remoteSet = false;
  bool _offerSent = false;
  final List<Map<String, dynamic>> _outCandidates = [];
  bool _renderersReady = false;
  bool _logged = false;
  bool _disposed = false;
  Timer? _ringTimer;
  DateTime? connectedAt;

  Future<void> _prepare() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
    _local = stream;
    localRenderer.srcObject = stream;

    final pc = await createPeerConnection({
      'iceServers': AppConfig.iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc = pc;

    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      final Map<String, dynamic> cand = {
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      };
      // Caller: offer ethuvare ayakkaathe candidates ayakkaruthu (order thettum).
      if (isCaller && !_offerSent) {
        _outCandidates.add(cand);
      } else {
        _send('candidate', cand);
      }
    };

    pc.onTrack = (RTCTrackEvent e) {
      if (e.streams.isNotEmpty) {
        remoteRenderer.srcObject = e.streams[0];
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _onConnected();
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (connected.value && !ended.value) status.value = 'Reconnecting…';
      } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _finish(
          'Connection failed',
          connectedAt != null ? 'completed' : 'unanswered',
        );
      }
    };

    // Video call aanenkil speaker, voice aanenkil ear-piece.
    try {
      await Helper.setSpeakerphoneOn(speaker.value);
    } catch (_) {}
  }

  void _onConnected() {
    if (connected.value || ended.value) return;
    _ringTimer?.cancel();
    connectedAt = DateTime.now();
    connected.value = true;
    status.value = 'Connected';
  }

  Future<void> startOutgoing() async {
    try {
      await _prepare();
      final pc = _pc!;
      final offerDesc = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': video,
      });
      await pc.setLocalDescription(offerDesc);
      await _send('offer', {
        'sdp': offerDesc.sdp,
        'type': offerDesc.type,
        'video': video,
      });
      _offerSent = true;
      final queued = List<Map<String, dynamic>>.from(_outCandidates);
      _outCandidates.clear();
      for (final c in queued) {
        await _send('candidate', c);
      }
      status.value = 'Ringing…';
      _ringTimer = Timer(const Duration(seconds: 45), () {
        if (!connected.value && !ended.value) hangup(unanswered: true);
      });
    } catch (e) {
      await _finish('Could not start the call', 'unanswered');
    }
  }

  Future<void> accept() async {
    try {
      await _prepare();
      final pc = _pc!;
      final o = offer!;
      await pc.setRemoteDescription(
        RTCSessionDescription(o['sdp'] as String?, o['type'] as String?),
      );
      _remoteSet = true;
      await _drainCandidates();
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': video,
      });
      await pc.setLocalDescription(answer);
      await _send('answer', {'sdp': answer.sdp, 'type': answer.type});
      status.value = 'Connecting…';
    } catch (e) {
      await _send('end', {});
      await _finish('Could not connect', 'missed');
    }
  }

  /// Aaro nammale vilichal "Decline" ammarthumbol.
  Future<void> reject() async {
    await _send('reject', {});
    await _finish('Declined', 'rejected');
  }

  /// Nammal "End" ammarthumbol.
  Future<void> hangup({bool unanswered = false}) async {
    if (ended.value) return;
    await _send('end', {});
    final st = connectedAt != null
        ? 'completed'
        : (unanswered ? 'unanswered' : 'cancelled');
    await _finish(unanswered ? 'No answer' : 'Call ended', st);
  }

  /// Opposite side-ninnulla signals.
  Future<void> handle(String type, Map<String, dynamic> p) async {
    if (ended.value) return;
    try {
      switch (type) {
        case 'answer':
          if (!isCaller || _remoteSet || _pc == null) return;
          _ringTimer?.cancel();
          await _pc!.setRemoteDescription(
            RTCSessionDescription(p['sdp'] as String?, p['type'] as String?),
          );
          _remoteSet = true;
          await _drainCandidates();
          status.value = 'Connecting…';
          break;
        case 'candidate':
          if (_remoteSet && _pc != null) {
            await _addCandidate(p);
          } else {
            _candidates.add(p);
          }
          break;
        case 'end':
          await _finish(
            'Call ended',
            connectedAt != null
                ? 'completed'
                : (isCaller ? 'cancelled' : 'missed'),
          );
          break;
        case 'reject':
          await _finish('Call declined', 'rejected');
          break;
        case 'busy':
          await _finish('User is busy on another call', 'unanswered');
          break;
      }
    } catch (_) {}
  }

  Future<void> _addCandidate(Map<String, dynamic> p) async {
    await _pc!.addCandidate(
      RTCIceCandidate(
        p['candidate'] as String?,
        p['sdpMid'] as String?,
        p['sdpMLineIndex'] as int?,
      ),
    );
  }

  Future<void> _drainCandidates() async {
    final pending = List<Map<String, dynamic>>.from(_candidates);
    _candidates.clear();
    for (final c in pending) {
      try {
        await _addCandidate(c);
      } catch (_) {}
    }
  }

  Future<void> _send(String type, Map<String, dynamic> payload) async {
    try {
      await sb.from('call_signals').insert({
        'call_id': callId,
        'from_id': myId,
        'to_id': peerId,
        'type': type,
        'payload': payload,
      });
    } catch (_) {}
  }

  Future<void> _log(String status) async {
    if (_logged) return;
    _logged = true;
    final dur = connectedAt == null
        ? 0
        : DateTime.now().difference(connectedAt!).inSeconds;
    try {
      await sb.from('call_logs').insert({
        'user_id': myId,
        'peer_id': peerId,
        'direction': isCaller ? 'outgoing' : 'incoming',
        'video': video,
        'status': status,
        'duration_s': dur,
      });
    } catch (_) {}
  }

  Future<void> _finish(String text, String logStatus) async {
    if (ended.value) return;
    _ringTimer?.cancel();
    status.value = text;
    connected.value = false;
    try {
      for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
        t.stop();
      }
    } catch (_) {}
    ended.value = true;
    await _log(logStatus);
    try {
      await sb.from('call_signals').delete().eq('call_id', callId);
    } catch (_) {}
  }

  void toggleMute() {
    muted.value = !muted.value;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted.value;
    }
  }

  void toggleCamera() {
    camOff.value = !camOff.value;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !camOff.value;
    }
  }

  Future<void> switchCamera() async {
    final v = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (v.isNotEmpty) {
      try {
        await Helper.switchCamera(v.first);
      } catch (_) {}
    }
  }

  Future<void> toggleSpeaker() async {
    speaker.value = !speaker.value;
    try {
      await Helper.setSpeakerphoneOn(speaker.value);
    } catch (_) {}
  }

  /// Screen close aakumbol vilikkanam. Ellaam clean cheyyum.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ringTimer?.cancel();
    try {
      for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
        t.stop();
      }
      await _local?.dispose();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      if (_renderersReady) {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
        await localRenderer.dispose();
        await remoteRenderer.dispose();
      }
    } catch (_) {}
    CallService.instance.release(callId);
  }
}

/// Incoming call kelkkunnu, call thudangunnu.
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  RealtimeChannel? _channel;
  final Map<String, CallSession> _sessions = {};
  final Map<String, List<Map<String, dynamic>>> _early = {};

  bool get busy => _sessions.isNotEmpty;

  void start() {
    stop();
    final me = myId;
    _channel = sb
        .channel('call-signals-$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_id',
            value: me,
          ),
          callback: (payload) => _onSignal(payload.newRecord),
        )
        .subscribe();
  }

  void stop() {
    final c = _channel;
    _channel = null;
    if (c != null) {
      sb.removeChannel(c);
    }
  }

  void release(String callId) {
    _sessions.remove(callId);
    _early.remove(callId);
  }

  Future<void> _onSignal(Map<String, dynamic> rec) async {
    final type = rec['type'] as String? ?? '';
    final callId = rec['call_id'] as String? ?? '';
    final from = rec['from_id'] as String? ?? '';
    final raw = rec['payload'];
    final payload = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    if (callId.isEmpty || from.isEmpty) return;

    if (type == 'offer') {
      if (_sessions.containsKey(callId)) return;
      if (busy) {
        try {
          await sb.from('call_signals').insert({
            'call_id': callId,
            'from_id': myId,
            'to_id': from,
            'type': 'busy',
            'payload': <String, dynamic>{},
          });
        } catch (_) {}
        return;
      }
      _early.putIfAbsent(callId, () => []);
      final prof = await ProfileCache.get(from);
      final s = CallSession(
        callId: callId,
        peerId: from,
        peerName: (prof['display_name'] ?? 'Unknown') as String,
        peerAvatar: prof['avatar_url'] as String?,
        video: payload['video'] == true,
        isCaller: false,
        offer: payload,
      );
      _sessions[callId] = s;
      final buffered = _early.remove(callId) ?? [];
      for (final e in buffered) {
        s.handle(e['type'] as String, e['payload'] as Map<String, dynamic>);
      }
      navKey.currentState?.push(
        MaterialPageRoute(builder: (_) => IncomingCallPage(session: s)),
      );
      return;
    }

    final existing = _sessions[callId];
    if (existing != null) {
      existing.handle(type, payload);
    } else if (type == 'candidate') {
      // Offer-inu munpe vannaal pidichu vekkum.
      _early.putIfAbsent(callId, () => []).add({'type': type, 'payload': payload});
    } else {
      _early[callId]?.add({'type': type, 'payload': payload});
    }
  }

  Future<void> startCall(
    BuildContext context,
    Map<String, dynamic> peer, {
    required bool video,
  }) async {
    if (busy) {
      snack(context, 'You are already on a call.');
      return;
    }
    // Friends thammil mathram call cheyyaan pattu.
    final fresh = await ProfileCache.get(peer['id'] as String, fresh: true);
    if (fresh['blocked_by_me'] == true || fresh['blocked_me'] == true) {
      if (context.mounted) snack(context, 'You cannot call this person.');
      return;
    }
    if (fresh['friend_status'] != 'friends') {
      if (context.mounted) {
        snack(
          context,
          'Calls are only for friends. Send a friend request first.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    final s = CallSession(
      callId:
          '${DateTime.now().microsecondsSinceEpoch}_${myId.substring(0, 8)}',
      peerId: peer['id'] as String,
      peerName: (peer['display_name'] ?? 'Unknown') as String,
      peerAvatar: peer['avatar_url'] as String?,
      video: video,
      isCaller: true,
    );
    _sessions[s.callId] = s;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => CallPage(session: s)));
    s.startOutgoing();
  }
}
