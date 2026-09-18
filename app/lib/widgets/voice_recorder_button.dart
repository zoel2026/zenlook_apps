import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Tombol mikrofon untuk pesan suara.
/// Long-press untuk mulai merekam, lepas untuk mengirim,
/// geser menjauh untuk membatalkan.
class VoiceRecorderButton extends StatefulWidget {
  const VoiceRecorderButton({
    super.key,
    required this.onRecordStart,
    required this.onRecordEnd,
    required this.onRecordCancel,
    this.recording,
  });

  final Future<bool> Function() onRecordStart;
  final Future<void> Function() onRecordEnd;
  final Future<void> Function() onRecordCancel;
  final bool? recording;

  @override
  State<VoiceRecorderButton> createState() => _VoiceRecorderButtonState();
}

class _VoiceRecorderButtonState extends State<VoiceRecorderButton> {
  bool _cancelled = false;
  double _dragDist = 0;

  Future<void> _onStart() async {
    _dragDist = 0;
    _cancelled = false;
    final ok = await widget.onRecordStart();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('voice_perm_fail'))),
      );
    }
  }

  void _onUpdate(LongPressMoveUpdateDetails d) {
    _dragDist += d.offsetFromOrigin.dx.abs();
    if (_dragDist > 120) _cancelled = true;
  }

  Future<void> _onEnd() async {
    if (_cancelled) {
      await widget.onRecordCancel();
    } else {
      await widget.onRecordEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _onStart(),
      onLongPressMoveUpdate: _onUpdate,
      onLongPressEnd: (_) => _onEnd(),
      onLongPressCancel: () => _onEnd(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: widget.recording == true
              ? const Color(0xFF3D5AFE)
              : Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.mic,
          color: widget.recording == true ? Colors.white : null,
          size: 20,
        ),
      ),
    );
  }
}