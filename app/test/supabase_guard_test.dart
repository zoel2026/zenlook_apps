import 'package:flutter_test/flutter_test.dart';
import 'package:zenlook/utils/supabase_guard.dart';

void main() {
  group('projectRefFromUrl', () {
    test('mengambil ref dari host <ref>.supabase.co', () {
      expect(
        projectRefFromUrl('https://ytmkhmsndfwmjlfyxiiw.supabase.co'),
        'ytmkhmsndfwmjlfyxiiw',
      );
    });

    test('mengabaikan spasi di sekitar URL', () {
      expect(
        projectRefFromUrl('  https://abc123.supabase.co  '),
        'abc123',
      );
    });

    test('null untuk kosong / null', () {
      expect(projectRefFromUrl(null), isNull);
      expect(projectRefFromUrl(''), isNull);
      expect(projectRefFromUrl('   '), isNull);
    });

    test('null untuk host yang bukan supabase.co', () {
      expect(projectRefFromUrl('https://example.com'), isNull);
      expect(projectRefFromUrl('https://abc123.notsupabase.co'), isNull);
    });

    test('null untuk URL tanpa skema valid', () {
      expect(projectRefFromUrl('not a url'), isNull);
    });
  });

  group('validateSupabaseUrl', () {
    test('null saat ref cocok dengan backend', () {
      expect(
        validateSupabaseUrl(
          url: 'https://ytmkhmsndfwmjlfyxiiw.supabase.co',
        ),
        isNull,
      );
    });

    test('error saat ref berbeda dari backend (R3)', () {
      final err = validateSupabaseUrl(
        url: 'https://pxifrxnkqxgzcgopgtvm.supabase.co',
      );
      expect(err, isNotNull);
      expect(err, contains('tidak cocok'));
    });

    test('error saat SUPABASE_URL kosong', () {
      expect(validateSupabaseUrl(url: null), contains('kosong'));
      expect(validateSupabaseUrl(url: ''), contains('kosong'));
    });

    test('error saat URL tidak valid / bukan host Supabase', () {
      expect(
        validateSupabaseUrl(url: 'https://example.com'),
        contains('tidak valid'),
      );
    });

    test('menghormati expectedProjectRef kustom', () {
      expect(
        validateSupabaseUrl(
          url: 'https://customref.supabase.co',
          expectedProjectRef: 'customref',
        ),
        isNull,
      );
    });
  });

  test('default expected ref = project backend', () {
    expect(kExpectedProjectRef, 'ytmkhmsndfwmjlfyxiiw');
  });
}
