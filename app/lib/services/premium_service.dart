import '../utils/supabase_guard.dart';

class PremiumService {
  static Future<bool> isPremium() async {
    final client = maybeClient();
    final user = client?.auth.currentUser;
    if (user == null) return false;
    try {
      final res = await client!
          .from('entitlements')
          .select('tier, expires_at')
          .eq('user_id', user.id)
          .maybeSingle();
      if (res == null) return false;
      final tier = res['tier'] as String?;
      final expiresAt = res['expires_at'] as String?;
      if (tier != 'pro') return false;
      if (expiresAt != null && expiresAt.isNotEmpty) {
        final dt = DateTime.tryParse(expiresAt);
        if (dt != null && dt.isBefore(DateTime.now())) {
          return false;
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static double maxNearbyRadiusFor(bool premium) {
    return premium ? 10.0 : 2.0;
  }

  static double radiusClamped(double requested, bool premium) {
    final max = maxNearbyRadiusFor(premium);
    if (requested.isNaN || requested.isInfinite) return max;
    if (requested < 0.1) return 0.1;
    if (requested > max) return max;
    return requested;
  }
}
