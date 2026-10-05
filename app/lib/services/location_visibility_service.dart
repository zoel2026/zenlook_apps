import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Hasil mengubah pengaturan "sembunyikan lokasi".
enum VisibilityResult {
  /// Berhasil.
  ok,

  /// Ditolak: bukan teman accepted, ada blokir, atau RLS menolak.
  notAllowed,

  /// Ditolak karena permintaan tidak valid (mis. menyembunyikan diri sendiri).
  invalid,

  /// Gagal karena alasan lain (offline, dsb).
  failed,
}

/// Pemeta error Postgrest -> [VisibilityResult] (pure, agar mudah diuji).
///
/// Pesan error dari RPC `set_location_hidden` sengaja ditolak dalam bahasa
/// Indonesia agar tidak perlu menambah tabel kode error baru di database.
VisibilityResult mapVisibilityErrorToResult({String? code, String? message}) {
  final msg = (message ?? '').toLowerCase();

  // RPC menolak menyembunyikan dari diri sendiri.
  if (msg.contains('diri sendiri')) return VisibilityResult.invalid;

  // RPC menolak kalau bukan teman accepted, atau salah satu saling memblokir.
  if (msg.contains('teman yang sudah accepted') ||
      msg.contains('saling memblokir')) {
    return VisibilityResult.notAllowed;
  }

  // RLS / tanpa sesi.
  if (code == '42501' || msg.contains('tidak terautentikasi')) {
    return VisibilityResult.notAllowed;
  }

  return VisibilityResult.failed;
}

/// Ambil id-id yang lokasinya sedang disembunyikan pengguna ini (pure).
Set<String> hiddenPeerIds(List<dynamic> rows) {
  final ids = <String>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final value = row['hidden_from_id'];
    if (value is String && value.isNotEmpty) ids.add(value);
  }
  return ids;
}

/// Kunci i18n untuk badge lokasi tersembunyi (pure).
String statusHiddenKey(bool hidden) => 'location_hidden_badge';

/// Kunci i18n untuk aksi berikutnya pada tombol mata (pure).
///
/// [currentlyHidden] true berarti tombol akan membuat lokasi terlihat kembali.
String visibilityToggleLabel(bool currentlyHidden) =>
    currentlyHidden ? 'show_location_to' : 'hide_location';

/// Service "sembunyikan lokasi dari teman tertentu".
///
/// Penyimpanan memakai RPC `set_location_hidden` karena tabel
/// `location_visibility` tidak punya policy insert — entri baru hanya boleh
/// dibuat server-side setelah memvalidasi bahwa target memang teman accepted
/// dan tidak ada blokir. Penegakan sebenarnya terjadi di RLS `locations` supaya
/// anon key tidak bisa membaca lokasi yang disembunyikan langsung lewat REST.
/// Lihat `docs/SPEC-hide-location.md`.
class LocationVisibilityService {
  static SupabaseClient? get _client => maybeClient();

  /// Salinkan / hentikan menyembunyikan lokasi ke [peerId].
  static Future<VisibilityResult> setHidden({
    required String peerId,
    required bool hidden,
  }) async {
    final c = _client;
    if (c == null) return VisibilityResult.failed;
    try {
      await c.rpc(
        'set_location_hidden',
        params: {'p_peer': peerId, 'p_hidden': hidden},
      );
      return VisibilityResult.ok;
    } on PostgrestException catch (e) {
      return mapVisibilityErrorToResult(code: e.code, message: e.message);
    } catch (_) {
      return VisibilityResult.failed;
    }
  }

  /// Daftar id yang lokasinya disembunyikan oleh pengguna ini.
  ///
  /// Mengembalikan set kosong bila belum ada (atau offline) supaya UI bisa
  /// menampilkan keadaan sebagai "belum ada yang disembunyikan".
  static Future<Set<String>> myHiddenPeerIds() async {
    final c = _client;
    final uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) return <String>{};
    try {
      final res = await c
          .from('location_visibility')
          .select('hidden_from_id')
          .eq('user_id', uid);
      return hiddenPeerIds(res);
    } catch (_) {
      return <String>{};
    }
  }
}