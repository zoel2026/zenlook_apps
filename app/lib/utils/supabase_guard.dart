import 'package:supabase_flutter/supabase_flutter.dart';

/// Mengembalikan SupabaseClient jika instance sudah diinisialisasi,
/// atau null jika belum (mis. saat aplikasi belum selesai startup
/// atau di lingkungan test) — tanpa melempar exception.
SupabaseClient? maybeClient() {
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

/// Project ref Supabase yang dipakai BACKEND (schema.sql, trigger push,
/// docs, CI) — lihat docs/CODE-REVIEW-REPORT.md item R3.
///
/// Bisa di-override saat build tanpa mengubah kode:
///   `flutter run --dart-define=EXPECTED_PROJECT_REF=<ref>`
const String kExpectedProjectRef = String.fromEnvironment(
  'EXPECTED_PROJECT_REF',
  defaultValue: 'ytmkhmsndfwmjlfyxiiw',
);

/// Ambil project ref dari URL Supabase.
///   https://ytmkhmsndfwmjlfyxiiw.supabase.co -> ytmkhmsndfwmjlfyxiiw
/// Mengembalikan null jika URL kosong / bukan host `<ref>.supabase.co`.
String? projectRefFromUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final host = Uri.tryParse(url.trim())?.host;
  if (host == null || host.isEmpty) return null;

  const suffix = '.supabase.co';
  if (!host.endsWith(suffix)) return null;

  final ref = host.substring(0, host.length - suffix.length);
  return ref.isEmpty ? null : ref;
}

/// Validasi `SUPABASE_URL` agar menunjuk ke project yang SAMA dengan backend.
/// Mengembalikan pesan error yang ramah, atau null jika cocok.
///
/// Ini mencegah masalah R3: app menunjuk project A sementara schema/trigger
/// push di-deploy ke project B -> push notification & nearby alert mati
/// diam-diam tanpa error yang jelas.
String? validateSupabaseUrl({
  String? url,
  String expectedProjectRef = kExpectedProjectRef,
}) {
  if (url == null || url.trim().isEmpty) {
    return 'SUPABASE_URL kosong. Isi app/.env (contoh: app/.env.example).';
  }
  final ref = projectRefFromUrl(url);
  if (ref == null) {
    return 'SUPABASE_URL tidak valid: "$url".\n'
        'Format yang diharapkan: https://<project-ref>.supabase.co';
  }
  if (ref != expectedProjectRef) {
    return 'Project ref Supabase tidak cocok (R3).\n\n'
        'App menunjuk ke     : $ref\n'
        'Backend/schema ke   : $expectedProjectRef\n\n'
        'App dan backend harus memakai project Supabase yang SAMA; jika tidak, '
        'push notification dan nearby alert akan gagal diam-diam.\n\n'
        'Perbaikan: samakan SUPABASE_URL di app/.env dengan backend, atau '
        'bangun ulang dengan --dart-define=EXPECTED_PROJECT_REF=<ref>';
  }
  return null;
}
