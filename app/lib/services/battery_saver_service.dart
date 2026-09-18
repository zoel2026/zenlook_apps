import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mode Hemat Baterai: kirim lokasi lebih jarang saat diam.
/// Mengurangi beban GPS + jaringan sehingga baterai lebih awet.
class BatterySaverService {
  static const prefKey = 'battery_saver_enabled';

  static final ValueNotifier<bool> enabled = ValueNotifier(false);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(prefKey) ?? false;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKey, value);
    } catch (_) {}
  }
}