import 'package:flutter_test/flutter_test.dart';
import 'package:zenlook/services/music_library.dart';

void main() {
  group('fileUri', () {
    test('mengubah path absolut menjadi file:// URI', () {
      expect(
        fileUri('C:\\Music\\lagu.mp3'),
        'file:///C:/Music/lagu.mp3',
      );
    });
  });

  group('tracksFromPaths', () {
    test('membangun daftar urut dengan judul = nama file (tanpa ekstensi)', () {
      final tracks = tracksFromPaths([
        r'C:\Music\lagu satu.mp3',
        r'/storage/music/alfa.mp3',
      ]);

      expect(tracks, hasLength(2));
      expect(tracks[0].title, 'lagu satu');
      expect(tracks[1].title, 'alfa');
      expect(tracks[0].uri, startsWith('file:///'));
      expect(tracks[0].uri, endsWith('lagu%20satu.mp3'));
    });

    test('dedup path yang sama', () {
      final tracks = tracksFromPaths([
        r'C:\Music\a.mp3',
        r'C:\Music\a.mp3',
      ]);
      expect(tracks, hasLength(1));
    });

    test('daftar kosong saat input kosong', () {
      expect(tracksFromPaths(const []), isEmpty);
    });
  });

  group('formatDuration', () {
    test('format mm:ss', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(formatDuration(const Duration(seconds: 754)), '12:34');
      expect(formatDuration(const Duration(seconds: 3600)), '60:00');
    });
  });
}