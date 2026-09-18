import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global handler tema — di-set saat app start, dipakai screen untuk
/// toggle tema tanpa perlu cascade param.
ThemeController? gThemeController;

/// Controller tema aplikasi (dark / light / system) dengan persistensi.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(super.mode);

  static const _prefKey = 'app_theme_mode';

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    final mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return ThemeController(mode);
  }

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    final prefs = await SharedPreferences.getInstance();
    final stored = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_prefKey, stored);
  }
}

/// Warna-warna tema yang dipakai lintas screen agar konsisten
/// di dark & light mode.
class AppColors {
  static const seed = Color(0xFF3D5AFE);
  static const accent = Color(0xFF3D5AFE);
  static const purple = Color(0xFF7C4DFF);
  static const teal = Color(0xFF26A69A);
  static const orange = Color(0xFFFF7043);

  static const bgDark = Color(0xFF0F1420);
  static const surfaceDark = Color(0xFF1A2130);
  static const bgLight = Color(0xFFF5F6FA);
  static const surfaceLight = Color(0xFFFFFFFF);
}

extension AppThemeContext on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Warna teks utama sesuai tema (putih di dark, hitam di light).
  Color get textPrimary => Theme.of(this).colorScheme.onSurface;

  /// Teks sekunder dengan opacity tertentu.
  Color textFaded(double opacity) =>
      Theme.of(this).colorScheme.onSurface.withValues(alpha: opacity);

  /// Surface (kartu / panel) sesuai tema.
  Color get surface => Theme.of(this).colorScheme.surface;

  /// Warna ikon/accent default.
  Color get accentColor => AppColors.accent;
}