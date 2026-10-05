import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Masa berlaku status yang bisa dipilih pengguna.
enum StatusTtl {
  oneHour(Duration(hours: 1)),
  fourHours(Duration(hours: 4)),
  eightHours(Duration(hours: 8));

  const StatusTtl(this.duration);

  final Duration duration;

  /// Masa berlaku bawaan saat pengguna menyimpan status.
  static const StatusTtl defaultTtl = StatusTtl.fourHours;
}

/// Batas panjang status. Nilainya sama dengan constraint di database
/// (`profiles_status_text_len`) supaya UI tidak mengirim teks yang pasti
/// ditolak backend.
const int kStatusMaxLength = 60;

/// Kunci i18n untuk pilihan masa berlaku (pure, agar mudah diuji).
String statusTtlKey(StatusTtl ttl) => switch (ttl) {
      StatusTtl.oneHour => 'status_ttl_1h',
      StatusTtl.fourHours => 'status_ttl_4h',
      StatusTtl.eightHours => 'status_ttl_8h',
    };

/// Apakah status masih aktif? (pure — inti aturan expire).
///
/// [text] kosong berarti tidak ada status. [expiresAt] yang `null` dianggap
/// aktif selamanya (ditulis tanpa masa berlaku, mis. lewat SQL Editor).
bool isStatusActive({
  required String? text,
  required DateTime? expiresAt,
  required DateTime now,
}) {
  if (text == null || text.trim().isEmpty) return false;
  if (expiresAt == null) return true;
  // Tepat pada batas waktu (`expiresAt == now`) masih dianggap aktif; status
  // baru dianggap hangus setelah waktu itu lewat.
  return !expiresAt.isBefore(now);
}

/// Teks status siap tampil, atau `null` kalau tidak ada / sudah hangus (pure).
String? activeStatusText({
  required String? text,
  required DateTime? expiresAt,
  required DateTime now,
}) {
  if (!isStatusActive(text: text, expiresAt: expiresAt, now: now)) {
    return null;
  }
  return text!.trim();
}

/// Emoji yang ditawarkan di pemilih status (tanpa package emoji picker).
const List<String> kStatusEmojiChoices = [
  '☕', '🍜', '📚', '🏀', '🎮', '😴', '🏠', '🎧', '🚶', '💻',
];

/// Gabungan emoji + teks status untuk ditampilkan (pure).
///
/// Mengembalikan `null` kalau status tidak ada / sudah hangus, sehingga
/// pemanggil cukup memeriksa satu nilai untuk menentukan tampil atau tidak.
String? statusLine({
  required String? emoji,
  required String? text,
  required DateTime? expiresAt,
  required DateTime now,
}) {
  final active = activeStatusText(text: text, expiresAt: expiresAt, now: now);
  if (active == null) return null;
  final trimmedEmoji = emoji?.trim();
  if (trimmedEmoji == null || trimmedEmoji.isEmpty) return active;
  return '$trimmedEmoji $active';
}

/// Service fitur "Status & Aktivitas" — status singkat milik pengguna sendiri.
///
/// Status disimpan di baris `profiles` (kolom `status_text`, `status_emoji`,
/// `status_expires_at`). Teman membacanya lewat policy `profiles_select_others`
/// yang sudah ada; menulis hanya bisa dilakukan pemilik lewat
/// `profiles_update_own`. Masa berlaku dicek di sisi client — tidak ada job
/// pembersihan di database, lihat `docs/SPEC-status.md`.
class StatusService {
  static SupabaseClient? get _client => maybeClient();

  /// Simpan status pengguna: [text] boleh kosong (berarti hapus), [emoji]
  /// opsional, dan [ttl] menentukan kapan status hangus.
  ///
  /// Mengembalikan `true` bila berhasil disimpan.
  static Future<bool> setStatus({
    required String? text,
    String? emoji,
    StatusTtl ttl = StatusTtl.defaultTtl,
  }) async {
    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) return clearStatus();

    final payload = <String, Object?>{
      'status_text': trimmed.length > kStatusMaxLength
          ? trimmed.substring(0, kStatusMaxLength)
          : trimmed,
      'status_emoji': (emoji == null || emoji.isEmpty) ? null : emoji,
      'status_expires_at':
          DateTime.now().add(ttl.duration).toIso8601String(),
    };
    return _write(payload);
  }

  /// Hapus status pengguna (teks, emoji, dan masa berlaku dikosongkan).
  static Future<bool> clearStatus() {
    return _write({
      'status_text': null,
      'status_emoji': null,
      'status_expires_at': null,
    });
  }

  static Future<bool> _write(Map<String, Object?> payload) async {
    final c = _client;
    final uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) return false;
    try {
      await c.from('profiles').update(payload).eq('id', uid);
      return true;
    } catch (_) {
      return false;
    }
  }
}