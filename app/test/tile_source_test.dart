import 'package:flutter_test/flutter_test.dart';
import 'package:zenlook/services/tile_source.dart';

void main() {
  group('resolveTileSource', () {
    test('memakai MAP_TILE_URL ketika dikonfigurasi', () {
      final source = resolveTileSource(
        {'MAP_TILE_URL': 'https://tiles.example.com/{z}/{x}/{y}.png'},
        allowOsmFallback: true,
      );

      expect(source.isEnabled, isTrue);
      expect(source.urlTemplate, 'https://tiles.example.com/{z}/{x}/{y}.png');
      expect(source.isOsmFallback, isFalse);
    });

    test('fallback OSM hanya kalau diizinkan (mode debug)', () {
      final source = resolveTileSource(
        const {},
        allowOsmFallback: true,
      );

      expect(source.isEnabled, isTrue);
      expect(source.isOsmFallback, isTrue);
      expect(source.urlTemplate, contains('openstreetmap.org'));
    });

    test('tanpa konfigurasi dan tanpa fallback: tile dimatikan', () {
      // Guard kebijakan tile publik OSM: di release, jangan diam-diam
      // memakai tile server publik yang melarang penggunaan apps.
      final source = resolveTileSource(
        const {},
        allowOsmFallback: false,
      );

      expect(source.isEnabled, isFalse);
      expect(source.urlTemplate, isNull);
    });

    test('MAP_TILE_URL string kosong diperlakukan sebagai tidak ada', () {
      final source = resolveTileSource(
        {'MAP_TILE_URL': ''},
        allowOsmFallback: false,
      );

      expect(source.isEnabled, isFalse);
    });

    test('meneruskan api key Stadia sebagai opsi api_key', () {
      final source = resolveTileSource(
        {
          'MAP_TILE_URL': 'https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png',
          'STADIA_API_KEY': 'stadia-key',
        },
        allowOsmFallback: false,
      );

      expect(source.options['api_key'], 'stadia-key');
    });

    test('meneruskan token Mapbox sebagai accessToken', () {
      final source = resolveTileSource(
        {
          'MAP_TILE_URL': 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}',
          'MAPBOX_ACCESS_TOKEN': 'mapbox-token',
        },
        allowOsmFallback: false,
      );

      expect(source.options['accessToken'], 'mapbox-token');
      expect(source.options.containsKey('api_key'), isFalse);
    });

    test('meneruskan key Maptiler sebagai key', () {
      final source = resolveTileSource(
        {
          'MAP_TILE_URL': 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png',
          'MAPTILER_API_KEY': 'maptiler-key',
        },
        allowOsmFallback: false,
      );

      expect(source.options['key'], 'maptiler-key');
    });
  });
}