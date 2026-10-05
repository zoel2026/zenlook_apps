import 'package:flutter_test/flutter_test.dart';
import 'package:zenlook/services/location_visibility_service.dart';

void main() {
  group('mapVisibilityErrorToResult', () {
    test('menolak bukan teman accepted', () {
      expect(
        mapVisibilityErrorToResult(
          code: 'P0001',
          message: 'Hanya bisa disembunyikan dari teman yang sudah accepted',
        ),
        VisibilityResult.notAllowed,
      );
    });

    test('menolak menyembunyikan dari diri sendiri', () {
      expect(
        mapVisibilityErrorToResult(
          code: 'P0001',
          message: 'Tidak bisa menyembunyikan lokasi dari diri sendiri',
        ),
        VisibilityResult.invalid,
      );
    });

    test('menolak saat ada blokir dua arah', () {
      expect(
        mapVisibilityErrorToResult(
          code: 'P0001',
          message: 'Tidak bisa disembunyikan dari user yang saling memblokir',
        ),
        VisibilityResult.notAllowed,
      );
    });

    test('menolak RLS / tidak terautentikasi', () {
      expect(
        mapVisibilityErrorToResult(code: '42501', message: null),
        VisibilityResult.notAllowed,
      );
    });

    test('gagal lain dianggap failed', () {
      expect(
        mapVisibilityErrorToResult(code: '08006', message: 'connection failure'),
        VisibilityResult.failed,
      );
    });
  });

  group('hiddenPeerIds', () {
    test('mengambil id tersembunyi dari baris apa pun', () {
      final ids = hiddenPeerIds([
        {'hidden_from_id': 'a'},
        {'hidden_from_id': 'b'},
        {'hidden_from_id': null},
      ]);
      expect(ids, {'a', 'b'});
    });

    test('baris kosong -> set kosong', () {
      expect(hiddenPeerIds(const []), isEmpty);
    });

    test('mengabaikan baris yang bukan map', () {
      expect(hiddenPeerIds(['bukan-map']), isEmpty);
    });
  });

  group('statusHiddenKey', () {
    test('satu kunci dipakai untuk menampilkan keadaan sembunyi', () {
      expect(statusHiddenKey(true), 'location_hidden_badge');
      expect(statusHiddenKey(false), 'location_hidden_badge');
    });
  });

  group('visibilityToggleLabel', () {
    test('label menjelaskan aksi berikutnya', () {
      expect(visibilityToggleLabel(true), 'show_location_to');
      expect(visibilityToggleLabel(false), 'hide_location');
    });
  });
}