import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/splash_screen.dart';
import 'services/audio_player_service.dart';
import 'services/battery_saver_service.dart';
import 'services/fcm_service.dart';
import 'services/locale_service.dart';
import 'services/push_service.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  await PushService.init();
  await FcmService.init();
  gAudioService = await AudioService.init(
    builder: () => AudioPlayerService(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.zenlook.channel.audio',
      androidNotificationChannelName: 'Audio playback',
    ),
  );
  final themeController = await ThemeController.load();
  final localeController = await LocaleController.load();
  gThemeController = themeController;
  gLocaleController = localeController;
  await BatterySaverService.init();
  runApp(
    ZenlyApps(
      themeController: themeController,
      localeController: localeController,
    ),
  );
}

class ZenlyApps extends StatelessWidget {
  const ZenlyApps({
    super.key,
    required this.themeController,
    required this.localeController,
  });

  final ThemeController themeController;
  final LocaleController localeController;

  ThemeData _baseTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? AppColors.bgDark : AppColors.bgLight,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: dark ? Colors.white : Colors.black87,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: dark ? Colors.white : Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            dark ? AppColors.surfaceDark : AppColors.surfaceLight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (context, mode, _) {
        return ValueListenableBuilder<AppLocale>(
          valueListenable: localeController,
          builder: (context, locale, _) {
            return MaterialApp(
              title: 'Zenlook Apps',
              debugShowCheckedModeBanner: false,
              theme: _baseTheme(Brightness.light),
              darkTheme: _baseTheme(Brightness.dark),
              themeMode: mode,
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}