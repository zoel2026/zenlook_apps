import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Service untuk memblokir / membuka blokir pengguna.
/// Berlaku dua arah: setelah diblokir, tidak bisa chat,
/// melihat lokasi, atau mengirim friend request.
class BlockService {
  static SupabaseClient? get _client => maybeClient();

  /// Blokir pengguna lain.
  static Future<void> blockUser(String userId, String blockedId) async {
    final c = _client;
    if (c == null) return;
    await c.from('blocked_users').insert({
      'user_id': userId,
      'blocked_id': blockedId,
    }).maybeSingle();
  }

  /// Buka blokir.
  static Future<void> unblockUser(String userId, String blockedId) async {
    final c = _client;
    if (c == null) return;
    await c
        .from('blocked_users')
        .delete()
        .eq('user_id', userId)
        .eq('blocked_id', blockedId);
  }

  /// Cek apakah antara dua user ada blokir (dua arah).
  static Future<bool> isBlocked(String userA, String userB) async {
    final c = _client;
    if (c == null) return false;
    try {
      final r = await c
          .from('blocked_users')
          .select('id')
          .or(
            'and(user_id.eq.$userA,blocked_id.eq.$userB),'
            'and(user_id.eq.$userB,blocked_id.eq.$userA)',
          )
          .maybeSingle();
      return r != null;
    } catch (_) {
      return false;
    }
  }

  /// Daftar pengguna yang memblokir saya (untuk filter konten).
  static Future<Set<String>> getUsersWhoBlockedMe(String myId) async {
    final c = _client;
    if (c == null) return {};
    try {
      final r = await c
          .from('blocked_users')
          .select('user_id')
          .eq('blocked_id', myId);
      return r.map((e) => e['user_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Daftar user yang saya blokir, berikut data profilnya.
  static Future<List<Map<String, dynamic>>> getMyBlockedUsers(
    String myId,
  ) async {
    final c = _client;
    if (c == null) return [];
    try {
      final r = await c
          .from('blocked_users')
          .select('blocked_id')
          .eq('user_id', myId);
      final ids = r.map((e) => e['blocked_id'] as String).toList();
      if (ids.isEmpty) return [];
      final profiles = await c
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .inFilter('id', ids);
      // Pertahankan urutan blokir.
      final byId = <String, Map<String, dynamic>>{};
      for (final p in profiles) {
        byId[p['id'] as String] = p;
      }
      return [for (final id in ids) if (byId[id] != null) byId[id]!];
    } catch (_) {
      return [];
    }
  }
}