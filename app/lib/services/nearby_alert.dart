/// Bantuan murni untuk fitur Nearby Alert (notifikasi user terdekat).
/// Tanpa dependensi Flutter — mudah di-unit-test.
library;

const int nearbyRadiusMin = 100;
const int nearbyRadiusMax = 1000;
const int nearbyRadiusDefault = 500;

/// Batasi radius user ke rentang yang diizinkan server (100-1000 m).
int clampRadius(int value) =>
    value.clamp(nearbyRadiusMin, nearbyRadiusMax);

/// Format jarak kompak: di bawah 1 km pakai meter, di atas pakai kilometer.
String formatDistance(int meters) {
  if (meters < 1000) return '$meters m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// Informasi push 'nearby' yang sudah diurai dari data FCM.
class NearbyAlertInfo {
  final String name;
  final int distanceM;
  final String? latitude;
  final String? longitude;

  const NearbyAlertInfo({
    required this.name,
    required this.distanceM,
    this.latitude,
    this.longitude,
  });

  /// Parse payload data-only FCM. Email null bila bukan tipe 'nearby'
  /// atau field wajib (name/distance_m) hilang/tidak valid.
  static NearbyAlertInfo? fromFcmData(Map<String, dynamic> data) {
    if (data['type'] != 'nearby') return null;
    final name = data['name'] as String?;
    final rawDistance = data['distance_m'] as String?;
    final distance = rawDistance == null ? null : int.tryParse(rawDistance);
    if (name == null || name.isEmpty || distance == null) return null;
    return NearbyAlertInfo(
      name: name,
      distanceM: distance,
      latitude: data['latitude'] as String?,
      longitude: data['longitude'] as String?,
    );
  }
}