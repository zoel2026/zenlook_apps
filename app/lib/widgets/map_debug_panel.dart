import 'package:flutter/material.dart';

import '../services/locale_service.dart';

/// Panel diagnostik internal — hanya muncul di debug mode.
/// Menampilkan info realtime: uid, izin, kirim posisi, jumlah teman,
/// status realtime, dan error load.
class MapDebugPanel extends StatefulWidget {
  const MapDebugPanel({
    super.key,
    required this.uidPreview,
    required this.permissionDenied,
    required this.sendInfo,
    required this.sendError,
    required this.friendCount,
    required this.positionCount,
    required this.realtimeStatus,
    this.loadError,
  });

  final String? uidPreview;
  final bool permissionDenied;
  final String sendInfo;
  final String? sendError;
  final int friendCount;
  final int positionCount;
  final String realtimeStatus;
  final String? loadError;

  @override
  State<MapDebugPanel> createState() => _MapDebugPanelState();
}

class _MapDebugPanelState extends State<MapDebugPanel> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      'uid: ${widget.uidPreview ?? '-'}',
      'izin lokasi: ${widget.permissionDenied ? "DITOLAK" : "ok"}',
      'kirim posisi: ${widget.sendInfo}',
      'teman: ${widget.friendCount} (berposisi: ${widget.positionCount})',
      'realtime: ${widget.realtimeStatus}',
      if (widget.loadError != null) 'load: ${widget.loadError}',
    ];

    return Positioned(
      top: 8,
      left: 8,
      child: GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final l in lines)
                      Text(
                        l,
                        style: TextStyle(
                          color: widget.sendError == null
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                )
              : Text(
                  context.l.t('debug'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
        ),
      ),
    );
  }
}
