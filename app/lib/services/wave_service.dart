import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Hasil pengiriman wave.
enum WaveResult {
  /// Wave terkirim.
  sent,

  /// Kena cooldown server-side (5 menit per pasangan).
  cooldown,

  /// Ditolak RLS: bukan teman accepted, atau ada blokir.
  blocked,

  /// Gagal karena alasan lain (offline, dsb).
  failed,
}

/// Peta error Postgrest -> [WaveResult] (pure, agar mudah diuji).
WaveResult waveResultFromError({String? code, String? message}) {
  final msg = (message ?? '').toLowerCase();
  // unique_violation dari trigger waves_cooldown_guard.
  if (code == '23505' || msg.contains('baru-baru ini')) {
    return WaveResult.cooldown;
  }
  // RLS menolak insert (bukan teman / diblokir).
  if (code == '42501' || msg.contains('row-level security')) {
    return WaveResult.blocked;
  }
  return WaveResult.failed;
}

/// Service fitur "Wave" / ping.
///
/// Kirim gelombang 👋 ke teman sebagai isyarat "di mana kamu? / ayo ketemuan".
/// Insert ke tabel `waves`; trigger DB mengirim push ke penerima. Penerima
/// yang app-nya terbuka juga menerima event realtime lewat [watchIncoming].
class WaveService {
  static SupabaseClient? get _client => maybeClient();

  /// Kirim wave dari [fromId] ke [toId].
  static Future<WaveResult> sendWave({
    required String fromId,
    required String toId,
  }) async {
    final c = _client;
    if (c == null) return WaveResult.failed;
    try {
      await c
          .from('waves')
          .insert({'sender_id': fromId, 'receiver_id': toId})
          .maybeSingle();
      return WaveResult.sent;
    } on PostgrestException catch (e) {
      return waveResultFromError(code: e.code, message: e.message);
    } catch (_) {
      return WaveResult.failed;
    }
  }

  /// Dengarkan wave masuk untuk [myId]. Mengembalikan channel (untuk
  /// di-unsubscribe saat dispose), atau null jika Supabase belum siap.
  ///
  /// [onWave] dipanggil dengan id pengirim. Beban dedupe/UI ada di pemanggil.
  static RealtimeChannel? watchIncoming({
    required String myId,
    required void Function(String senderId) onWave,
  }) {
    final c = _client;
    if (c == null) return null;
    try {
      return c.channel('waves_$myId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'waves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myId,
          ),
          callback: (payload) {
            final sender = payload.newRecord['sender_id'] as String?;
            if (sender != null && sender.isNotEmpty) onWave(sender);
          },
        )
        ..subscribe();
    } catch (_) {
      return null;
    }
  }
}
