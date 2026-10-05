/// Sumber layer peta (tile server).
///
/// Peta memakai provider berlisensi (Stadia/Mapbox/Maptiler) yang dikonfigurasi
/// lewat `app/.env` (`MAP_TILE_URL` + key-nya). Tile publik OpenStreetMap
/// **tidak boleh** dipakai pada rilis: [kebijakan penggunaan tile OSM] melarang
/// traffic dari aplikasi, dan tile publik dipakai untuk demo saja. Karena itu
/// fallback ke OSM hanya diizinkan pada mode debug — lihat
/// [resolveTileSource] parameter `allowOsmFallback`.
///
/// [kebijakan penggunaan tile OSM]: https://operations.osmfoundation.org/policies/tiles
class TileSource {
  const TileSource._({
    required this.urlTemplate,
    this.options = const <String, String>{},
    this.isOsmFallback = false,
  });

  /// Provider tile terkonfigurasi (berlisensi).
  const TileSource.configured(
    String url, {
    Map<String, String> options = const <String, String>{},
  }) : this._(urlTemplate: url, options: options);

  /// Tile publik OSM — hanya untuk pengembangan/debug.
  const TileSource.osmForDevelopment()
      : this._(urlTemplate: _osmTemplate, isOsmFallback: true);

  /// Tanpa tile sama sekali: belum dikonfigurasi pada mode rilis.
  const TileSource.unconfigured() : this._(urlTemplate: null);

  static const String _osmTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Template URL tile, atau `null` bila tidak ada tile yang boleh dipakai.
  final String? urlTemplate;

  /// Parameter tambahan template (mis. `api_key`, `accessToken`).
  final Map<String, String> options;

  /// `true` bila memakai tile publik OSM (hanya debug).
  final bool isOsmFallback;

  bool get isEnabled => urlTemplate != null;
}

/// Menentukan sumber tile dari environment aplikasi.
///
/// [allowOsmFallback] harus `kDebugMode`, sehingga rilis tidak pernah diam-diam
/// memakai tile publik yang lisensinya melarang penggunaan aplikasi.
TileSource resolveTileSource(
  Map<String, String> env, {
  required bool allowOsmFallback,
}) {
  final url = env['MAP_TILE_URL']?.trim();
  if (url != null && url.isNotEmpty) {
    return TileSource.configured(url, options: _tileOptions(env));
  }
  return allowOsmFallback
      ? const TileSource.osmForDevelopment()
      : const TileSource.unconfigured();
}

/// Kunci API provider tile, mengikuti urutan prioritas di `app/.env.example`.
Map<String, String> _tileOptions(Map<String, String> env) {
  final stadia = env['STADIA_API_KEY']?.trim();
  if (stadia != null && stadia.isNotEmpty) return {'api_key': stadia};

  final mapbox = env['MAPBOX_ACCESS_TOKEN']?.trim();
  if (mapbox != null && mapbox.isNotEmpty) return {'accessToken': mapbox};

  final maptiler = env['MAPTILER_API_KEY']?.trim();
  if (maptiler != null && maptiler.isNotEmpty) return {'key': maptiler};

  return const <String, String>{};
}