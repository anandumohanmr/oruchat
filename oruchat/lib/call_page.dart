import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' hide Navigator;

import 'call_service.dart';
import 'utils.dart';

const _callGradient = BoxDecoration(
  gradient: LinearGradient(
    colors: [Color(0xFF6500E8), Color(0xFF2B0073)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),
);

class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.session});

  final CallSession session;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final CallSession s = widget.session;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    s.ended.addListener(_onEnded);
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && s.connected.value) setState(() {});
    });
  }

  void _onEnded() {
    if (!s.ended.value) return;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    s.ended.removeListener(_onEnded);
    if (!s.ended.value) {
      s.hangup();
    }
    s.dispose();
    super.dispose();
  }

  String get statusText {
    if (s.connected.value && s.connectedAt != null) {
      return fmtDuration(DateTime.now().difference(s.connectedAt!).inSeconds);
    }
    return s.status.value;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) s.hangup();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: s.connected,
                builder: (context, isConnected, _) {
                  if (s.video && isConnected) {
                    return RTCVideoView(
                      s.remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    );
                  }
                  return Container(decoration: _callGradient);
                },
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  ValueListenableBuilder<bool>(
                    valueListenable: s.connected,
                    builder: (context, isConnected, _) {
                      final showAvatar = !(s.video && isConnected);
                      return Column(
                        children: [
                          if (showAvatar)
                            Avatar(
                              name: s.peerName,
                              url: s.peerAvatar,
                              radius: 56,
                            ),
                          if (showAvatar) const SizedBox(height: 16),
                          Text(
                            s.peerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ValueListenableBuilder<String>(
                            valueListenable: s.status,
                            builder: (context, _, __) => Text(
                              statusText,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 36),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 18,
                      runSpacing: 18,
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: s.muted,
                          builder: (context, v, _) => _RoundBtn(
                            icon: v ? Icons.mic_off_rounded : Icons.mic_rounded,
                            active: v,
                            onTap: s.toggleMute,
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: s.speaker,
                          builder: (context, v, _) => _RoundBtn(
                            icon: v
                                ? Icons.volume_up_rounded
                                : Icons.hearing_rounded,
                            active: v,
                            onTap: s.toggleSpeaker,
                          ),
                        ),
                        if (s.video)
                          ValueListenableBuilder<bool>(
                            valueListenable: s.camOff,
                            builder: (context, v, _) => _RoundBtn(
                              icon: v
                                  ? Icons.videocam_off_rounded
                                  : Icons.videocam_rounded,
                              active: v,
                              onTap: s.toggleCamera,
                            ),
                          ),
                        if (s.video)
                          _RoundBtn(
                            icon: Icons.cameraswitch_rounded,
                            active: false,
                            onTap: s.switchCamera,
                          ),
                        _RoundBtn(
                          icon: Icons.call_end_rounded,
                          active: false,
                          background: Colors.red,
                          onTap: s.hangup,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (s.video)
              Positioned(
                top: 0,
                right: 12,
                child: SafeArea(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: s.camOff,
                    builder: (context, off, _) => off
                        ? const SizedBox.shrink()
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 104,
                              height: 150,
                              child: RTCVideoView(
                                s.localRenderer,
                                mirror: true,
                                objectFit: RTCVideoViewObjectFit
                                    .RTCVideoViewObjectFitCover,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.icon,
    required this.active,
    required this.onTap,
    this.background,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ?? (active ? Colors.white : Colors.white24),
        ),
        child: Icon(
          icon,
          color: background != null
              ? Colors.white
              : (active ? purple : Colors.white),
          size: 28,
        ),
      ),
    );
  }
}

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({super.key, required this.session});

  final CallSession session;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  late final CallSession s = widget.session;
  Timer? ringTimer;
  bool accepted = false;

  @override
  void initState() {
    super.initState();
    s.ended.addListener(_onEnded);
    _buzz();
    ringTimer = Timer.periodic(const Duration(seconds: 2), (_) => _buzz());
  }

  void _buzz() {
    HapticFeedback.vibrate();
    SystemSound.play(SystemSoundType.alert);
  }

  void _onEnded() {
    if (s.ended.value && !accepted && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    ringTimer?.cancel();
    s.ended.removeListener(_onEnded);
    if (!accepted) s.dispose();
    super.dispose();
  }

  void _accept() {
    accepted = true;
    ringTimer?.cancel();
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => CallPage(session: s)));
    s.accept();
  }

  Future<void> _decline() async {
    ringTimer?.cancel();
    await s.reject();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: _callGradient,
          width: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                Avatar(name: s.peerName, url: s.peerAvatar, radius: 60),
                const SizedBox(height: 20),
                Text(
                  s.peerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.video ? 'Incoming video call…' : 'Incoming voice call…',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(flex: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 56),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          _RoundBtn(
                            icon: Icons.call_end_rounded,
                            active: false,
                            background: Colors.red,
                            onTap: _decline,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Decline',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          _RoundBtn(
                            icon: s.video
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            active: false,
                            background: Colors.green,
                            onTap: _accept,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Accept',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
