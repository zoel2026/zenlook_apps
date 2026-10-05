import 'package:flutter_test/flutter_test.dart';
import 'package:zenlook/services/status_service.dart';

void main() {
  final now = DateTime(2026, 10, 5, 12);

  group('StatusTtl', () {
    test('durasi mengikuti pilihan pengguna', () {
      expect(StatusTtl.oneHour.duration, const Duration(hours: 1));
      expect(StatusTtl.fourHours.duration, const Duration(hours: 4));
      expect(StatusTtl.eightHours.duration, const Duration(hours: 8));
    });

    test('default empat jam', () {
      expect(StatusTtl.defaultTtl, StatusTtl.fourHours);
    });
  });

  group('kStatusMaxLength', () {
    test('sesuai constraint di database (60 karakter)', () {
      expect(kStatusMaxLength, 60);
    });
  });

  group('statusTtlKey', () {
    test('memetakan tiap masa berlaku ke kunci i18n', () {
      expect(statusTtlKey(StatusTtl.oneHour), 'status_ttl_1h');
      expect(statusTtlKey(StatusTtl.fourHours), 'status_ttl_4h');
      expect(statusTtlKey(StatusTtl.eightHours), 'status_ttl_8h');
    });
  });

  group('statusLine', () {
    test('menggabungkan emoji dan teks', () {
      expect(
        statusLine(
          emoji: '☕',
          text: 'Di kantin',
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        '☕ Di kantin',
      );
    });

    test('tanpa emoji hanya teksnya', () {
      expect(
        statusLine(
          emoji: null,
          text: 'Di kantin',
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        'Di kantin',
      );
      expect(
        statusLine(
          emoji: '  ',
          text: 'Di kantin',
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        'Di kantin',
      );
    });

    test('null saat status sudah hangus', () {
      expect(
        statusLine(
          emoji: '☕',
          text: 'Di kantin',
          expiresAt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isNull,
      );
    });
  });

  group('kStatusEmojiChoices', () {
    test('daftar emoji tidak kosong dan unik', () {
      expect(kStatusEmojiChoices, isNotEmpty);
      expect(kStatusEmojiChoices.toSet().length, kStatusEmojiChoices.length);
    });
  });

  group('isStatusActive', () {
    test('teks kosong dianggap tidak aktif', () {
      expect(
        isStatusActive(
          text: '',
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(
        isStatusActive(text: null, expiresAt: null, now: now),
        isFalse,
      );
    });

    test('aktif saat teks ada dan belum kedaluwarsa', () {
      expect(
        isStatusActive(
          text: 'Di kantin',
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('tidak aktif setelah masa berlaku habis', () {
      expect(
        isStatusActive(
          text: 'Di kantin',
          expiresAt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isFalse,
      );
    });

    test('tepat pada batas waktu masih aktif', () {
      expect(
        isStatusActive(text: 'Di kantin', expiresAt: now, now: now),
        isTrue,
      );
    });

    test('teks ada tapi tanpa masa berlaku dianggap aktif', () {
      // Ditulis manual lewat SQL Editor / tidak ada expire -> tetap tampil.
      expect(isStatusActive(text: 'Di kantin', expiresAt: null, now: now), isTrue);
    });
  });

  group('activeStatusText', () {
    test('mengembalikan teks yang masih aktif', () {
      expect(
        activeStatusText(
          text: 'Lagi ngerjain skripsi',
          expiresAt: now.add(const Duration(hours: 2)),
          now: now,
        ),
        'Lagi ngerjain skripsi',
      );
    });

    test('mengembalikan null saat kedaluwarsa', () {
      expect(
        activeStatusText(
          text: 'Lagi ngerjain skripsi',
          expiresAt: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isNull,
      );
    });

    test('memangkas spasi di tepi', () {
      expect(
        activeStatusText(
          text: '  di kantin  ',
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        'di kantin',
      );
    });

    test('teks berisi spasi saja dianggap kosong', () {
      expect(
        activeStatusText(
          text: '   ',
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        isNull,
      );
    });
  });
}