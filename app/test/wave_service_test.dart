import 'package:flutter_test/flutter_test.dart';
import 'package:zenlook/services/wave_service.dart';

void main() {
  group('waveResultFromError', () {
    test('unique_violation (23505) -> cooldown', () {
      expect(
        waveResultFromError(code: '23505', message: 'duplicate key value'),
        WaveResult.cooldown,
      );
    });

    test('pesan cooldown Indonesia -> cooldown', () {
      expect(
        waveResultFromError(
          message: 'Sudah mengirim wave ke pengguna ini baru-baru ini',
        ),
        WaveResult.cooldown,
      );
    });

    test('RLS 42501 -> blocked', () {
      expect(
        waveResultFromError(
          code: '42501',
          message: 'new row violates row-level security policy',
        ),
        WaveResult.blocked,
      );
    });

    test('pesan row-level security -> blocked', () {
      expect(
        waveResultFromError(message: 'row-level security policy for table'),
        WaveResult.blocked,
      );
    });

    test('error tak dikenal -> failed', () {
      expect(waveResultFromError(code: '500', message: 'boom'), WaveResult.failed);
      expect(waveResultFromError(), WaveResult.failed);
    });
  });
}
