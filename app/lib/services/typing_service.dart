import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Indikator "sedang mengetik..." via Supabase Realtime broadcast.
/// Satu channel per pasangan chat (urutan id diurutkan agar sama
/// dari kedua sisi). Broadcast bersifat ephemeral — tidak direkam di DB.
class TypingService {
  TypingService({required this.peerId, required this.myId});

  final String peerId;
  final String myId;

  RealtimeChannel? _channel;
  Timer? _typingThrottle;
  bool _lastSentTyping = false;
  bool _disposed = false;

  /// Dipanggil saat peer mulai / berhenti mengetik.
  void Function(bool typing)? onPeerTyping;

  static String _channelName(String a, String b) {
    final ids = [a, b]..sort();
    return 'zenlook_typing_${ids.join('_')}';
  }

  Future<void> start() async {
    final client = maybeClient();
    if (client == null) return;
    _disposed = false;
    try {
      _channel = client.channel(_channelName(myId, peerId), opts: const RealtimeChannelConfig(ack: true))
        ..onBroadcast(
          event: 'typing',
          callback: (payload) {
            final uid = payload['uid'] as String?;
            final typing = (payload['typing'] ?? false) as bool;
            if (uid == null || uid == myId) return;
            onPeerTyping?.call(typing);
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  void _send(bool typing) {
    final client = maybeClient();
    if (_disposed || client == null || _channel == null) return;
    if (_lastSentTyping == typing) return;
    _lastSentTyping = typing;
    try {
      _channel!.sendBroadcastMessage(
        event: 'typing',
        payload: {'uid': myId, 'typing': typing},
      );
    } catch (_) {}
  }

  /// Panggil saat user mengetik. Throttle maksimal 1 event/2 detik.
  void notifyTyping() {
    if (_typingThrottle != null) return;
    _send(true);
    _typingThrottle = Timer(const Duration(seconds: 2), () {
      _typingThrottle = null;
    });
  }

  /// Panggil saat user berhenti mengetik (kirim dikirim / text kosong).
  void notifyStopped() {
    _typingThrottle?.cancel();
    _typingThrottle = null;
    _send(false);
  }

  void dispose() {
    _disposed = true;
    _typingThrottle?.cancel();
    _typingThrottle = null;
    try {
      _channel?.unsubscribe();
    } catch (_) {}
    _channel = null;
  }
}