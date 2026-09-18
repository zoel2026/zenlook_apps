import '../utils/supabase_guard.dart';

/// Pencarian pengguna di sekitar via RPC get_nearby_users.
class NearbyService {
  /// Scan pengguna non-teman dalam radius [radiusKm] (paksa 2km dari UI).
  static Future<List<Map<String, dynamic>>> scan(
    double lat,
    double lng, {
    double radiusKm = 2,
  }) async {
    final c = maybeClient();
    if (c == null) return [];
    final r = await c.rpc(
      'get_nearby_users',
      params: {'p_lat': lat, 'p_lng': lng, 'p_radius_km': radiusKm},
    );
    final list = r as List?;
    if (list == null) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Kirim permintaan pertemanan ke user dekat.
  static Future<void> sendRequest(String userId, String peerId) async {
    final c = maybeClient();
    if (c == null) return;
    await c.from('friendships').insert({
      'user_id': userId,
      'friend_id': peerId,
      'status': 'pending',
    });
  }
}