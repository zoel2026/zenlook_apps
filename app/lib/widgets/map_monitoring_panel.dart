import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../screens/chat_detail_screen.dart';
import '../services/locale_service.dart';
import '../services/wave_service.dart';
import '../utils/supabase_guard.dart';
import '../widgets/user_avatar.dart';
import 'map_models.dart';

/// Panel informasi teman yang sedang di-monitoring di peta.
/// Menampilkan nama, status online, jarak, koordinat, dan tombol aksi
/// (chat, tampilkan jalur, tutup).
class MapMonitoringPanel extends StatelessWidget {
  const MapMonitoringPanel({
    super.key,
    required this.friend,
    required this.peerId,
    required this.myPosition,
    required this.onClose,
    required this.onToggleTrack,
    required this.showTrack,
    required this.trackPointCount,
  });

  final FriendData friend;
  final String peerId;
  final LatLng? myPosition;
  final VoidCallback onClose;
  final VoidCallback onToggleTrack;
  final bool showTrack;
  final int trackPointCount;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2130),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                UserAvatar(
                  name: friend.name,
                  avatarUrl: friend.avatar,
                  radius: 22,
                  backgroundColor: const Color(0xFF7C4DFF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              friend.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _isOnline
                                  ? Colors.greenAccent.withValues(alpha: 0.15)
                                  : Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              l.t(_isOnline ? 'online' : 'offline'),
                              style: TextStyle(
                                color: _isOnline
                                    ? Colors.greenAccent
                                    : Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (friend.activityLine != null)
                        Text(
                          friend.activityLine!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF3D5AFE),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        '${l.t('last_update')}: '
                        '${_lastUpdateText(l, friend.updatedAt)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.waving_hand_outlined),
                  color: const Color(0xFFFFC107),
                  tooltip: l.t('wave_send_tooltip'),
                  onPressed: () => _sendWave(context),
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  color: const Color(0xFF3D5AFE),
                  tooltip: l.t('chat'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatDetailScreen(
                        peerId: peerId,
                        peerName: friend.name,
                        peerAvatar: friend.avatar,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: Colors.white70,
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _stat(
                  Icons.route,
                  l.t('distance_from_you'),
                  _distanceText,
                ),
                _stat(
                  Icons.place_outlined,
                  l.t('coordinates'),
                  friend.position == null
                      ? '-'
                      : '${friend.position!.latitude.toStringAsFixed(4)}, '
                          '${friend.position!.longitude.toStringAsFixed(4)}',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onToggleTrack,
                  icon: Icon(
                    showTrack ? Icons.route : Icons.route_outlined,
                    size: 18,
                    color: showTrack ? Colors.greenAccent : Colors.white70,
                  ),
                  label: Text(
                    l.t(showTrack ? 'hide_track' : 'show_track'),
                    style: TextStyle(
                      color: showTrack ? Colors.greenAccent : Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Spacer(),
                if (showTrack)
                  Text(
                    l.t('track_points', args: [trackPointCount]),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendWave(BuildContext context) async {
    final l = context.l;
    final me = maybeClient()?.auth.currentUser?.id;
    if (me == null) return;
    final result = await WaveService.sendWave(fromId: me, toId: peerId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.t(waveMessageKey(result)))),
    );
  }

  bool get _isOnline {
    if (friend.status != 'online') return false;
    final t = friend.updatedAt;
    if (t == null) return false;
    return DateTime.now().difference(t).inMinutes < 2;
  }

  String get _distanceText {
    final myPos = myPosition;
    if (myPos == null || friend.position == null) return '-';
    final d = Geolocator.distanceBetween(
      myPos.latitude,
      myPos.longitude,
      friend.position!.latitude,
      friend.position!.longitude,
    );
    if (d < 1000) return '${d.round()} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  String _lastUpdateText(AppLocalizations l, DateTime? t) {
    if (t == null) return '-';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 10) return l.t('just_now');
    if (d.inMinutes < 1) return l.t('secs_ago', args: [d.inSeconds]);
    if (d.inHours < 1) return l.t('mins_ago', args: [d.inMinutes]);
    return DateFormat('HH:mm').format(t);
  }

  Widget _stat(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF3D5AFE), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
