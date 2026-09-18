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
