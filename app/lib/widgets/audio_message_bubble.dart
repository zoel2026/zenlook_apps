import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../services/audio_player_service.dart';

/// Bubble pesan audio (MP3/M4A/AAC/WAV) yang diputar lewat
/// [AudioPlayerService] global — mendukung playback background dan
/// kontrol media (notifikasi/lock screen).
class AudioMessageBubble extends StatefulWidget {
  const AudioMessageBubble({
    super.key,
    required this.queue,
    required this.index,
    required this.name,
    required this.duration,
    required this.mine,
    this.onPlayStart,
  });

  /// Antrean seluruh audio message dari chat (urutan riwayat).
  final List<MediaItem> queue;

  /// Index file ini di dalam [queue].
  final int index;

  final String name;
  final double? duration;
  final bool mine;

  /// Dipanggil saat mulai memutar (untuk pause pemutar suara lain).
  final VoidCallback? onPlayStart;

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final fg = Colors.white;
    return StreamBuilder<PlaybackState>(
      stream: gAudioService?.playbackState,
      initialData: gAudioService?.playbackState.value,
      builder: (context, snap) {
        final state = snap.data;
        final isCurrent = gAudioService?.mediaItem.value?.id ==
            _mediaItem.id;
        final playing = state?.playing == true && isCurrent;
        final position = state?.updatePosition ?? Duration.zero;
        final total = _mediaItem.duration ??
            Duration(seconds: widget.duration?.round() ?? 0);
        final progress = isCurrent
            ? (total.inMilliseconds == 0
                ? 0.0
                : position.inMilliseconds / total.inMilliseconds)
            : 0.0;
        final label = isCurrent
            ? '${_fmt(position)} / ${_fmt(total)}'
            : _fmt(total);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    playing ? Icons.pause_circle : Icons.play_circle,
                    color: fg,
                  ),
                  onPressed: () => _toggle(state),
                ),
                SizedBox(
                  width: 110,
                  child: LinearProgressIndicator(
                    value: _progress(progress),
                    minHeight: 3,
                    backgroundColor: fg.withValues(alpha: 0.25),
                    color: fg,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.45,
              ),
              child: Text(
                widget.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _progress(double raw) => raw.clamp(0, 1);

  MediaItem get _mediaItem =>
      widget.index >= 0 && widget.index < widget.queue.length
          ? widget.queue[widget.index]
          : MediaItem(
              id: '',
              title: widget.name,
              duration: Duration(seconds: widget.duration?.round() ?? 0),
            );

  Future<void> _toggle(PlaybackState? state) async {
    final service = gAudioService;
    if (service == null) return;
    final item = _mediaItem;
    if (item.id.isEmpty) return;
    final isCurrent = service.mediaItem.value?.id == item.id;
    if (isCurrent && service.playbackState.value.playing) {
      await service.pause();
      return;
    }
    if (isCurrent) {
      await service.play();
      return;
    }
    widget.onPlayStart?.call();
    final queue = widget.queue;
    final index = widget.index.clamp(0, queue.length - 1);
    await service.loadQueue(queue, index: index);
    await service.play();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds % 60;
    final m = d.inMinutes;
    return m > 0 ? '$m:${s.toString().padLeft(2, '0')}' : '0:$s';
  }
}