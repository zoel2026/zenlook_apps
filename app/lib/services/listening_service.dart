import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Indikator "sedang mendengarkan music mp3" via Supabase Realtime broadcast.
///
/// Satu channel per pasangan chat (urutan id diurutkan agar sama dari kedua
/// sisi). Broadcast bersifat ephemeral — tidak direkam di DB. Payload:
/// `{ uid, listening: bool, name: String? }` dengan [name] = judul file MP3.
///
/// Hanya dipicu oleh audio message (`is_audio`, player `audio_service`),
/// bukan voice message (`is_voice`).
class ListeningService {
  ListeningService({required this.peerId, required this.myId});

  final String peerId;
  final String myId;

  RealtimeChannel? _channel;
  String? _lastSentName;
  bool _disposed = false;

  /// Dipanggil saat peer mulai / berhenti mendengarkan. [name] null = berhenti.
  void Function(String? name)? onPeerListening;

  static String _channelName(String a, String b) {
    final ids = [a, b]..sort();
    return 'zenlook_listening_${ids.join('_')}';
  }

  Future<void> start() async {
    final client = maybeClient();
    if (client == null) return;
    _disposed = false;
    try {
      _channel = client.channel(
        _channelName(myId, peerId),
        opts: const RealtimeChannelConfig(ack: true),
      )
        ..onBroadcast(
          event: 'listening',
          callback: (payload) {
            final uid = payload['uid'] as String?;
            if (uid == null || uid == myId) return;
            onPeerListening?.call(payload['name'] as String?);
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  void _send(bool listening, String? name) {
    final client = maybeClient();
    if (_disposed || client == null || _channel == null) return;
    if (listening && name == _lastSentName) return;
    _lastSentName = listening ? name : null;
    try {
      _channel!.sendBroadcastMessage(
        event: 'listening',
        payload: {'uid': myId, 'listening': listening, 'name': name},
      );
    } catch (_) {}
  }

  /// Panggil saat user mulai mendengarkan [name] (judul file MP3).
  void notifyListening(String name) {
    _send(true, name);
  }

  /// Panggil saat user pause / stop / menutup chat.
  void notifyStopped() {
    _send(false, null);
  }

  void dispose() {
    notifyStopped();
    _disposed = true;
    try {
      _channel?.unsubscribe();
    } catch (_) {}
    _channel = null;
    _lastSentName = null;
  }
}