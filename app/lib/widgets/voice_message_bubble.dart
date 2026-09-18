import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Buble pesan suara: tombol play, progress bar, dan durasi.
class VoiceMessageBubble extends StatefulWidget {
  const VoiceMessageBubble({
    super.key,
    required this.voiceUrl,
    required this.duration,
    required this.mine,
    this.onPlayStart,
  });

  final String voiceUrl;
  final double? duration;
  final bool mine;

  /// Dipanggil saat mulai memutar (untuk pause pemutar audio lain).
  final VoidCallback? onPlayStart;

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  AudioPlayer? _player;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _posSub = _player!.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _durSub = _player!.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _stateSub = _player!.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final p = _player;
    if (p == null) return;
    if (_playing) {
      await p.pause();
    } else {
      final url = widget.voiceUrl;
      if (url.isEmpty) return;
      widget.onPlayStart?.call();
      if (_position == Duration.zero) {
        await p.play(UrlSource(url));
      } else {
        await p.resume();
      }
    }
  }

  double get _progress {
    final total = _duration;
    if (total == null || total.inMilliseconds == 0) return 0;
    return (_position.inMilliseconds / total.inMilliseconds).clamp(0, 1);
  }

  String get _label {
    final total = _duration ?? Duration(seconds: widget.duration?.round() ?? 0);
    return _position == Duration.zero
        ? _fmt(_duration ?? total)
        : '${_fmt(_position)} / ${_fmt(_duration ?? total)}';
  }

  String _fmt(Duration d) {
    final s = d.inSeconds % 60;
    final m = d.inMinutes;
    return m > 0 ? '$m:${s.toString().padLeft(2, '0')}' : '0:$s';
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine ? Colors.white : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                _playing ? Icons.pause_circle : Icons.play_circle,
                color: fg,
              ),
              onPressed: _toggle,
            ),
            SizedBox(
              width: 90,
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 3,
                backgroundColor: fg.withValues(alpha: 0.25),
                color: fg,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _label,
              style: TextStyle(
                color: fg.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        Text(
          context.l.t('voice_message'),
          style: TextStyle(
            color: fg.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}