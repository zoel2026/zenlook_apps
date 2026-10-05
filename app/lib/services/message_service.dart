import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';

/// Cakupan penghapusan pesan.
enum DeleteScope {
  /// Hanya disembunyikan untuk pengguna yang menghapus.
  onlyMe,

  /// Dikosongkan untuk semua orang (isi pesan tidak bisa dipulihkan).
  everyone;

  /// `true` bila penghapusan juga memengaruhi perangkat lawan.
  bool get affectsOtherPerson => this == DeleteScope.everyone;
}

/// Hasil penghapusan pesan.
enum DeleteResult {
  /// Berhasil.
  ok,

  /// Ditolak: bukan pesan milik sendiri, atau pesan sudah dihapus.
  notAllowed,

  /// Gagal karena alasan lain (offline, dsb).
  failed,
}

/// Kunci i18n untuk item menu hapus (pure, agar mudah diuji).
String deleteMessageKey(DeleteScope scope) => switch (scope) {
      DeleteScope.onlyMe => 'delete_only_me',
      DeleteScope.everyone => 'delete_for_everyone',
    };

/// Kunci i18n untuk dialog konfirmasi (pure, agar mudah diuji).
String confirmDeleteMessageKey(DeleteScope scope) => switch (scope) {
      DeleteScope.onlyMe => 'delete_confirm_only_me',
      DeleteScope.everyone => 'delete_confirm_everyone',
    };

/// Pemeta error Postgrest -> [DeleteResult] (pure, agar mudah diuji).
DeleteResult mapDeleteErrorToResult({String? code, String? message}) {
  final msg = (message ?? '').toLowerCase();
  // RLS: policy messages_update_own hanya mengizinkan baris milik sendiri,
  // dan zero row dari `.select()` berarti pesan bukan milik pengguna.
  if (code == '42501' ||
      code == 'PGRST116' ||
      msg.contains('row-level security') ||
      msg.contains('no rows')) {
    return DeleteResult.notAllowed;
  }
  // Trigger messages_no_undelete: pesan yang dihapus tidak bisa dipulihkan.
  if (code == 'P0001' || msg.contains('tidak bisa dipulihkan')) {
    return DeleteResult.notAllowed;
  }
  return DeleteResult.failed;
}

/// Argumen untuk [visibleMessageContent].
class MessageContentArgs {
  const MessageContentArgs({
    required this.body,
    required this.isDeleted,
    required this.now,
  });

  final String body;

  /// `true` bila pesan sudah dihapus untuk semua orang.
  final bool isDeleted;

  final DateTime now;
}

/// Isi pesan yang boleh ditampilkan (pure).
///
/// Mengembalikan `null` bila pesan kosong atau sudah dihapus, supaya pemanggil
/// bisa menampilkan pengganti ("Pesan ini dihapus") tanpa logika tambahan.
String? visibleMessageContent(MessageContentArgs args) {
  if (args.isDeleted) return null;
  final body = args.body.trim();
  return body.isEmpty ? null : body;
}

/// Service hapus pesan (soft delete).
///
/// Baris `messages` tidak pernah dihapus secara fisik: kolom `is_deleted`
/// diisi `true` supaya urutan cursor pagination tetap utuh. Penghapusan untuk
/// semua orang dikosongkan isinya juga oleh trigger `messages_no_undelete`,
/// sehingga isi lama tidak bisa dipulihkan — termasuk lewat jalur lain seperti
/// service role. Lihat `docs/SPEC-delete-message.md`.
class MessageService {
  static SupabaseClient? get _client => maybeClient();

  /// Hapus pesan milik [messageId].
  ///
  /// [scope] menentukan apakah lawan juga kehilangan pesan tersebut. Bila
  /// update tidak menyentuh satu baris pun (pesan bukan milik pengguna, atau
  /// RLS menolak), hasilnya [DeleteResult.notAllowed].
  static Future<DeleteResult> deleteMessage({
    required String messageId,
    required DeleteScope scope,
  }) async {
    final c = _client;
    final uid = c?.auth.currentUser?.id;
    if (c == null || uid == null) return DeleteResult.failed;

    try {
      final res = await c
          .from('messages')
          .update({
            'is_deleted': true,
            'deleted_at': DateTime.now().toIso8601String(),
            // Kosong untuk "hanya saya": tidak ada jejak untuk lawan.
            'deleted_by': scope.affectsOtherPerson ? uid : null,
          })
          .eq('id', messageId)
          .eq('sender_id', uid)
          .select('id');

      if (res.isEmpty) return DeleteResult.notAllowed;
      return DeleteResult.ok;
    } on PostgrestException catch (e) {
      return mapDeleteErrorToResult(code: e.code, message: e.message);
    } catch (_) {
      return DeleteResult.failed;
    }
  }
}