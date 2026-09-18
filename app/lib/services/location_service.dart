import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  static Future<bool> ensurePermission() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Meminta izin lokasi "Allow all the time" untuk mode berbagi selalu.
  /// Android mensyaratkan izin while-in-use sudah disetujui lebih dulu.
  static Future<bool> ensureAlwaysPermission() async {
    try {
      var status = await Permission.locationAlways.status;
      if (status.isGranted) return true;
      if (!await Permission.locationWhenInUse.isGranted) {
        final inUse = await Permission.locationWhenInUse.request();
        if (!inUse.isGranted) return false;
      }
      status = await Permission.locationAlways.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isAlwaysGranted() async {
    try {
      return await Permission.locationAlways.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  static Future<Position?> getCurrentPosition() async {
    if (!await ensurePermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Stream posisi berkelanjutan.
  ///
  /// [distanceFilter] dalam meter — jarak tempuh minimum sebelum event
  /// posisi baru dikeluarkan (lebih besar = lebih hemat baterai).
  ///
  /// Di Android dipasang sebagai *foreground service* (muncul notifikasi
  /// tetap) sehingga update lokasi tetap jalan saat aplikasi di
  /// background — tanpa perlu izin ACCESS_BACKGROUND_LOCATION.
  /// Service otomatis berhenti ketika stream dibatalkan (logout/app ditutup).
  static Stream<Position> positionStream({int distanceFilter = 5}) {
    LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Zenlook aktif',
          notificationText:
              'Berbagi lokasi tetap berjalan di latar belakang',
          notificationChannelName: 'Berbagi Lokasi',
          enableWakeLock: true,
          enableWifiLock: true,
          setOngoing: true,
        ),
      );
    } else {
      settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
