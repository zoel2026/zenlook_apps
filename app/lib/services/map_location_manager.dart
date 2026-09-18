import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/battery_saver_service.dart';
import '../services/location_service.dart';

/// Mengelola stream posisi user: subscribe ke GPS, kirim upsert ke Supabase,
/// dan jalankan keep-alive agar posisi selalu ter-update.
///
/// Mode Hemat Baterai (BatterySaverService):
///  - interval keep-alive lebih jarang (30 detik vs 15 detik)
///  - distanceFilter GPS lebih longgar (10 m vs 5 m)
///  - threshold kirim lebih tinggi saat bergerak
class LocationManager {
  LocationManager({
    required this.supabase,
    required this.userId,
    required this.onPosition,
    required this.onError,
  }) {
    _listener = () {
      _subscribeStream();
      _startKeepAlive();
    };
    BatterySaverService.enabled.addListener(_listener!);
  }

  final SupabaseClient supabase;
  final String userId;

  /// Dipanggil setiap kali posisi user berubah (untuk update UI).
  final void Function(Position pos) onPosition;

  /// Dipanggil saat ada error kirim posisi.
  final void Function(String error) onError;

  StreamSubscription<Position>? _positionSub;
  Timer? _keepAliveTimer;
  VoidCallback? _listener;

  double? _lastSentLat;
  double? _lastSentLng;
  DateTime? _lastSendAt;
  bool _disposed = false;

  bool get _batterySaver => BatterySaverService.enabled.value;

  Duration get _keepAliveInterval => _batterySaver
      ? const Duration(seconds: 30)
      : const Duration(seconds: 15);

  int get _distanceFilter => _batterySaver ? 10 : 5;

  double get _minMove => _batterySaver ? 10 : 5;

  /// Mulai stream GPS + keep-alive.
  Future<void> start() async {
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      onPosition(pos);
      await _upsert(pos);
    }
    _subscribeStream();
    _startKeepAlive();
  }

  void _subscribeStream() {
    _positionSub?.cancel();
    try {
      _positionSub = LocationService.positionStream(
        distanceFilter: _distanceFilter,
      ).listen(
        (pos) {
          _upsert(pos);
          onPosition(pos);
        },
        onError: (Object _) {},
      );
    } catch (_) {}
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) async {
      if (_disposed) return;
      final pos = await LocationService.getCurrentPosition();
      if (pos != null && !_disposed) {
        await _upsert(pos);
        onPosition(pos);
      }
    });
  }

  Future<void> _upsert(Position pos) async {
    final now = DateTime.now();
    if (_lastSentLat != null && _lastSendAt != null) {
      final moved = Geolocator.distanceBetween(
          _lastSentLat!, _lastSentLng!, pos.latitude, pos.longitude);
      if (moved < _minMove && now.difference(_lastSendAt!).inSeconds < 60) {
        return;
      }
    }
    try {
      await supabase.from('locations').upsert({
        'user_id': userId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
      }, onConflict: 'user_id');
      _lastSentLat = pos.latitude;
      _lastSentLng = pos.longitude;
      _lastSendAt = now;
      onError('');
    } catch (e) {
      onError(e.toString());
    }
  }

  /// Ambil posisi terakhir (buat keep-alive manual).
  Future<Position?> getCurrentPosition() =>
      LocationService.getCurrentPosition();

  /// Set status online/offline di profiles.
  Future<void> setOnline(bool online) async {
    try {
      await supabase
          .from('profiles')
          .update({'status': online ? 'online' : 'offline'})
          .eq('id', userId);
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    if (_listener != null) {
      BatterySaverService.enabled.removeListener(_listener!);
      _listener = null;
    }
    _positionSub?.cancel();
    _keepAliveTimer?.cancel();
  }
}
