import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Service untuk melaporkan pengguna (spam / tidak pantas / pelecehan).
/// Maksimal 1 laporan per target per 24 jam.
class ReportService {
  static SupabaseClient? get _client => maybeClient();

  static const alasan = <String, String>{
    'spam': 'Spam',
    'inappropriate': 'Konten tidak pantas',
    'harassment': 'Pelecehan',
    'fake_account': 'Akun palsu',
    'other': 'Lainnya',
  };

  /// Kirim laporan. Throw PostgrestException jika sudah pernah lapor
  /// dalam 24 jam (di-enforce server-side via trigger user_reports_24h_guard).
  static Future<void> reportUser(
    String reporterId,
    String reportedId,
    String reason,
  ) async {
    final c = _client;
    if (c == null) throw Exception('Unauthenticated');
    await c.from('user_reports').insert({
      'reporter_id': reporterId,
      'reported_id': reportedId,
      'reason': reason,
    });
  }

  /// Cek apakah user sudah melaporkan target dalam 24 jam terakhir.
  static Future<bool> hasReportedToday(String reporterId, String reportedId) async {
    final c = _client;
    if (c == null) return false;
    try {
      final since = DateTime.now()
          .subtract(const Duration(hours: 24))
          .toUtc()
          .toIso8601String();
      final r = await c
          .from('user_reports')
          .select('id')
          .eq('reporter_id', reporterId)
          .eq('reported_id', reportedId)
          .gte('created_at', since)
          .maybeSingle();
      return r != null;
    } catch (_) {
      return false;
    }
  }
}