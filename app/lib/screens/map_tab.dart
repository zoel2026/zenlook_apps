import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/location_service.dart';
import '../services/locale_service.dart';
import '../services/map_location_manager.dart';
import '../utils/supabase_guard.dart';
import '../widgets/back_button_widget.dart';
import '../widgets/map_debug_panel.dart';
import '../widgets/map_models.dart';
import '../widgets/map_monitoring_panel.dart';
import '../widgets/nearby_users_sheet.dart';
import '../widgets/user_avatar.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => MapTabState();
}

class MapTabState extends State<MapTab> {
  final _mapController = MapController();
  SupabaseClient get supabase => Supabase.instance.client;

  LocationManager? _locationManager;
  RealtimeChannel? _channel;
  RealtimeChannel? _friendshipChannel;
  Timer? _pollTimer;

  LatLng? _myPosition;
  double? _myAccuracy;
  String? _monitoringId;
  String? _myAvatar;
  String _myName = '';
  final Map<String, FriendData> _friends = {};
  bool _permissionDenied = false;
  bool _gpsOff = false;
  bool _showTrack = false;
  bool _mapReady = false;
  List<LatLng> _trackPoints = [];

  String? _sendError;
  String? _loadError;
  String _realtimeStatus = '-';
  DateTime? _lastSendAt;

  String? get _myId => maybeClient()?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    if (!await LocationService.isLocationServiceEnabled()) {
      if (!mounted) return;
      setState(() => _gpsOff = true);
    }
    final granted = await LocationService.ensurePermission();
    if (!granted) {
      setState(() => _permissionDenied = true);
      return;
    }
    _startLocationStream();
    _loadMyProfile();
    await _loadFriends();
    _subscribeRealtime();
    _subscribeFriendships();
    _startPolling();
  }

  void _startLocationStream() async {
    final uid = _myId;
    if (uid == null) return;

    _locationManager = LocationManager(
      supabase: supabase,
      userId: uid,
      onPosition: (pos) {
        if (!mounted) return;
        setState(() {
          _myPosition = LatLng(pos.latitude, pos.longitude);
          _myAccuracy = pos.accuracy;
        });
        if (_mapReady) {
          _mapController.move(
            _myPosition!,
            _mapController.camera.zoom < 14
                ? 14
                : _mapController.camera.zoom,
          );
        }
      },
      onError: (error) {
        _sendError = error.isEmpty ? null : error;
        _lastSendAt = error.isEmpty ? DateTime.now() : _lastSendAt;
        if (mounted) setState(() {});
      },
    );
    await _locationManager?.start();
    _locationManager?.setOnline(true);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    // Fallback refresh yang jarang (60 detik) — update utama dari Realtime.
    // Frekuensi rendah supaya hemat baterai/data, bukan utama seperti dulu.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        if (!mounted) return;
        _loadFriends();
      },
    );
  }

  Future<void> _loadMyProfile() async {
    try {
      final uid = _myId;
      if (uid == null) return;
      final res = await supabase
          .from('profiles')
          .select('username, full_name, avatar_url')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || res == null) return;
      setState(() {
        _myName = ((res['username'] ?? res['full_name'] ?? '?') as String);
        _myAvatar = (res['avatar_url'] ?? '') as String;
      });
    } catch (_) {}
  }

  void _subscribeFriendships() {
    try {
      _friendshipChannel = supabase.channel('friendships_map')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) {
              _loadFriends();
              return;
            }
            final raw = payload.newRecord;
            final rec = Map<String, dynamic>.from(raw);
            final involved =
                rec['user_id'] == _myId || rec['friend_id'] == _myId;
            if (!involved) return;
            _loadFriends();
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  Future<void> reloadFriends() async {
    await _loadFriends();
    if (mounted) setState(() {});
  }

  Future<void> _loadFriends() async {
    try {
      final fs = await supabase
          .from('friendships')
          .select('user_id, friend_id')
          .eq('status', 'accepted')
          .or('user_id.eq.$_myId,friend_id.eq.$_myId');
      final friendIds = fs
          .map<String>((f) => f['user_id'] == _myId
              ? f['friend_id'] as String
              : f['user_id'] as String)
          .toSet()
          .toList();

      if (friendIds.isEmpty) {
        if (!mounted) return;
        setState(() => _friends.clear());
        return;
      }

      final friends = await supabase
          .from('profiles')
          .select('id, username, full_name, status, avatar_url, locations(*)')
          .inFilter('id', friendIds);

      if (!mounted) return;
      setState(() {
        _friends.clear();
        _loadError = null;
        for (final f in friends) {
          final id = f['id'] as String;
          final data = FriendData(
            name: (f['username'] ?? f['full_name'] ?? 'Teman') as String,
          );
          data.avatar = (f['avatar_url'] ?? '') as String;
          data.status = (f['status'] ?? 'offline') as String;
          final locs = f['locations'];
          Map<String, dynamic>? loc;
          if (locs is List && locs.isNotEmpty) {
            final first = locs.first;
            if (first is Map<String, dynamic>) {
              loc = first;
            } else if (first is Map) {
              loc = Map<String, dynamic>.from(first);
            }
          } else if (locs is Map<String, dynamic>) {
            loc = locs;
          }
          if (loc != null && loc['latitude'] != null) {
            data.position = LatLng(
              (loc['latitude'] as num).toDouble(),
              (loc['longitude'] as num).toDouble(),
            );
            data.updatedAt =
                DateTime.tryParse((loc['updated_at'] ?? '') as String)
                    ?.toLocal();
          }
          _friends[id] = data;
        }
      });
    } on PostgrestException catch (e) {
      debugPrint('MapTab._loadFriends gagal: ${e.message}');
      if (!mounted) return;
      setState(() => _loadError = 'DB: ${e.message}');
    } catch (e) {
      debugPrint('MapTab._loadFriends error: $e');
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    }
  }

  void _subscribeRealtime() {
    try {
      _channel = supabase.channel('locations')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'locations',
          callback: (payload) {
            final rec = Map<String, dynamic>.from(payload.newRecord);
            final userId = rec['user_id'] as String?;
            if (userId == null || userId == _myId) return;
            final f = _friends[userId];
            if (f == null) return;
            final lat = (rec['latitude'] as num).toDouble();
            final lng = (rec['longitude'] as num).toDouble();
            f.position = LatLng(lat, lng);
            f.updatedAt =
                DateTime.tryParse((rec['updated_at'] ?? '') as String)
                    ?.toLocal();
            if (!mounted) return;
            if (_monitoringId == userId) {
              if (_showTrack) _trackPoints.add(LatLng(lat, lng));
              _moveCameraTo(f.position!);
            }
            setState(() {});
          },
        )
        ..subscribe((status, error) {
          _realtimeStatus = status.name;
          if (error != null) debugPrint('MapTab realtime error: $error');
          if (mounted) setState(() {});
        });
    } catch (_) {}
  }

  void _selectFriend(String id) {
    final f = _friends[id];
    setState(() => _monitoringId = id);
    if (f?.position != null) _moveCameraTo(f!.position!);
  }

  void _closeMonitoring() {
    setState(() {
      _monitoringId = null;
      _showTrack = false;
      _trackPoints = [];
    });
  }

  Future<void> _toggleTrack() async {
    setState(() => _showTrack = !_showTrack);
    if (_showTrack) {
      if (_monitoringId != null) await _loadTrack(_monitoringId!);
    } else {
      setState(() => _trackPoints = []);
    }
  }

  Future<void> _loadTrack(String userId) async {
    try {
      final res = await supabase
          .from('location_history')
          .select('latitude, longitude')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(300);
      final pts = res
          .map<LatLng>((r) => LatLng(
                (r['latitude'] as num).toDouble(),
                (r['longitude'] as num).toDouble(),
              ))
          .toList()
          .reversed
          .toList();
      if (!mounted) return;
      setState(() => _trackPoints = pts);
    } catch (_) {}
  }

  void _moveCameraTo(LatLng p) {
    _mapController.move(
      p,
      _mapController.camera.zoom < 15 ? 15 : _mapController.camera.zoom,
    );
  }

  void _centerOnMe() {
    if (_myPosition == null) return;
    _moveCameraTo(_myPosition!);
  }

  DateTime? _lastScan;

  Future<void> _scanNearby() async {
    final now = DateTime.now();
    if (_lastScan != null &&
        now.difference(_lastScan!) < const Duration(seconds: 30)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l.t('scan_too_soon'))),
        );
      }
      return;
    }
    final pos = _myPosition;
    if (pos == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('scan_failed'))),
      );
      return;
    }
    _lastScan = now;
    try {
      await showNearbyUsersSheet(
        context,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l.t('scan_failed'))),
      );
    }
  }

  String _lastUpdateText(AppLocalizations l, DateTime? t) {
    if (t == null) return '-';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 10) return l.t('just_now');
    if (d.inMinutes < 1) return l.t('secs_ago', args: [d.inSeconds]);
    if (d.inHours < 1) return l.t('mins_ago', args: [d.inMinutes]);
    return DateFormat('HH:mm').format(t);
  }

  /// 'Online' hanya valid jika status memang online DAN lokasi terakhir
  /// diperbarui maksimal 2 menit lalu.
  bool _isEffectivelyOnline(FriendData f) {
    if (f.status != 'online') return false;
    final t = f.updatedAt;
    if (t == null) return false;
    return DateTime.now().difference(t).inMinutes < 2;
  }

  List<Marker> _buildMarkers() {
    return _friends.entries
        .where((e) => e.value.position != null)
        .map((e) {
      final f = e.value;
      final online = _isEffectivelyOnline(f);
      return Marker(
        point: f.position!,
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => _selectFriend(e.key),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 2,
                  ),
                ),
                child: UserAvatar(
                  name: f.name,
                  avatarUrl: f.avatar,
                  radius: 19,
                  backgroundColor: const Color(0xFFFF7043),
                ),
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Icon(
                  Icons.circle,
                  color: online ? Colors.greenAccent : Colors.grey,
                  size: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  @override
  void dispose() {
    _locationManager?.setOnline(false);
    _locationManager?.dispose();
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    _friendshipChannel?.unsubscribe();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monitoringFriend = _friends[_monitoringId];
    final positionCount =
        _friends.values.where((f) => f.position != null).length;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButtonWidget(icon: Icons.menu),
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Text(context.l.t('realtime_map')),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myPosition ?? const LatLng(-6.2, 106.8),
              initialZoom: 14,
              onMapReady: () => _mapReady = true,
            ),
            children: [
              TileLayer(
                urlTemplate: _getTileUrl(),
                additionalOptions: _getTileOptions(),
                userAgentPackageName: 'com.zenlook.app',
              ),
              PolylineLayer(
                polylines: [
                  if (_trackPoints.isNotEmpty)
                    Polyline(
                      points: _trackPoints,
                      strokeWidth: 4,
                      color: const Color(0xCC7C4DFF),
                    ),
                ],
              ),
              if (_myPosition != null)
                MarkerLayer(
                  markers: [
                    ..._buildMarkers(),
                    Marker(
                      point: _myPosition!,
                      width: 48,
                      height: 48,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3D5AFE)
                              .withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF3D5AFE),
                            width: 3,
                          ),
                        ),
                        child: UserAvatar(
                          name: _myName,
                          avatarUrl: _myAvatar,
                          radius: 14,
                          backgroundColor: const Color(0xFF3D5AFE),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_myAccuracy != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      context.l.t('accuracy', args: [_myAccuracy!.round()]),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                FloatingActionButton(
                  heroTag: 'locate',
                  onPressed: _centerOnMe,
                  backgroundColor: const Color(0xFF3D5AFE),
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'nearby',
                  onPressed: _scanNearby,
                  backgroundColor: const Color(0xFF7C4DFF),
                  child: const Icon(Icons.radar, size: 20),
                ),
              ],
            ),
          ),
          if (_permissionDenied || _gpsOff)
            Positioned(
              left: 16,
              right: 16,
              bottom: 100,
              child: Card(
                color: Colors.black.withValues(alpha: 0.75),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _permissionDenied
                        ? context.l.t('permission_denied')
                        : context.l.t('gps_off'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          if (monitoringFriend != null)
            MapMonitoringPanel(
              friend: monitoringFriend,
              peerId: _monitoringId!,
              myPosition: _myPosition,
              onClose: _closeMonitoring,
              onToggleTrack: _toggleTrack,
              showTrack: _showTrack,
              trackPointCount: _trackPoints.length,
            ),
          if (kDebugMode)
            MapDebugPanel(
              uidPreview: _myId?.substring(0, 8),
              permissionDenied: _permissionDenied,
              sendInfo: _sendError != null
                  ? 'ERROR: $_sendError'
                  : _lastSendAt != null
                      ? 'OK ${_lastUpdateText(context.l, _lastSendAt)}'
                      : context.l.t('never'),
              sendError: _sendError,
              friendCount: _friends.length,
              positionCount: positionCount,
              realtimeStatus: _realtimeStatus,
              loadError: _loadError,
            ),
        ],
      ),
    );
  }

  String _getTileUrl() {
    final url = dotenv.env['MAP_TILE_URL'];
    if (url != null && url.isNotEmpty) {
      return url;
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  Map<String, String> _getTileOptions() {
    final stadiaKey = dotenv.env['STADIA_API_KEY'];
    final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
    final maptilerKey = dotenv.env['MAPTILER_API_KEY'];

    if (stadiaKey != null && stadiaKey.isNotEmpty) {
      return {'api_key': stadiaKey};
    }
    if (mapboxToken != null && mapboxToken.isNotEmpty) {
      return {'accessToken': mapboxToken};
    }
    if (maptilerKey != null && maptilerKey.isNotEmpty) {
      return {'key': maptilerKey};
    }
    return {};
  }
}
