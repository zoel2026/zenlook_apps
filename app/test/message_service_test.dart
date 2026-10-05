import 'package:flutter_test/flutter_test.dart';
import 'package:zenlook/services/message_service.dart';

void main() {
  group('deleteMessageKey', () {
    test('memetakan cakupan hapus ke kunci i18n', () {
      expect(deleteMessageKey(DeleteScope.onlyMe), 'delete_only_me');
      expect(deleteMessageKey(DeleteScope.everyone), 'delete_for_everyone');
    });
  });

  group('confirmDeleteMessageKey', () {
    test(' Judul konfirmasi berbeda per cakupan', () {
      expect(
        confirmDeleteMessageKey(DeleteScope.onlyMe),
        'delete_confirm_only_me',
      );
      expect(
        confirmDeleteMessageKey(DeleteScope.everyone),
        'delete_confirm_everyone',
      );
    });
  });

  group('mapDeleteErrorToResult', () {
    test('menolak pesan yang tidak ditemukan (42501 / tidak ada baris)', () {
      // RLS update hanya mengizinkan baris milik sendiri.
      expect(
        mapDeleteErrorToResult(
          code: '42501',
          message: 'new row violates row-level security policy',
        ),
        DeleteResult.notAllowed,
      );
      expect(
        mapDeleteErrorToResult(code: 'PGRST116', message: 'no rows found'),
        DeleteResult.notAllowed,
      );
    });

    test('menolak penghapusan ulang (trigger guard)', () {
      expect(
        mapDeleteErrorToResult(
          code: 'P0001',
          message: 'pesan yang dihapus tidak bisa dipulihkan',
        ),
        DeleteResult.notAllowed,
      );
    });

    test('gagal lain dianggap failed', () {
      expect(
        mapDeleteErrorToResult(code: '08006', message: 'connection failure'),
        DeleteResult.failed,
      );
    });
  });

  group('visibleMessageContent', () {
    final now = DateTime(2026, 10, 5, 12);
    final base = MessageContentArgs(
      body: 'halo',
      isDeleted: false,
      now: now,
    );

    test('pesan biasa tampil isinya', () {
      expect(visibleMessageContent(base), 'halo');
    });

    test('pesan dihapus tidak menampilkan isi', () {
      expect(
        visibleMessageContent(
          MessageContentArgs(body: 'rahasia', isDeleted: true, now: now),
        ),
        isNull,
      );
    });

    test('pesan kosong tidak menghasilkan string kosong', () {
      expect(
        visibleMessageContent(
          MessageContentArgs(body: '   ', isDeleted: false, now: now),
        ),
        isNull,
      );
    });
  });

  group('DeleteScope', () {
    test('everyone berarti hapus untuk semua orang', () {
      expect(DeleteScope.everyone.affectsOtherPerson, isTrue);
      expect(DeleteScope.onlyMe.affectsOtherPerson, isFalse);
    });
  });
}