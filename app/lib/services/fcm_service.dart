import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_guard.dart';
import 'push_service.dart';

/// Handler untuk pesan data-only yang datang saat aplikasi
/// terminated/background. Wajib top-level function.
/// Catatan: isolat background punya state terpisah —
/// PushService.activePeerId tidak tersedia di sini, jadi selalu tampilkan.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  final d = message.data;
  final title = d['title'] as String?;
  final body = d['body'] as String?;
  if (title == null || body == null) return;
  try {
    await PushService.show(title, body, senderId: d['sender_id'] as String?);
  } catch (_) {}
}

class FcmService {
  static bool _initialized = false;
  static String? _currentToken;
  static StreamSubscription<RemoteMessage>? _messageSub;
  static StreamSubscription<String>? _tokenRefreshSub;
  static StreamSubscription<AuthState>? _authSub;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Inisialisasi FCM. Aman dipanggil kapan pun — jika Firebase belum
  /// dikonfigurasi (google-services.json belum ada), semua dilewati diam-diam.
  static Future<void> init() async {
    if (_initialized || !_supported) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (_) {
      // Belum ada konfigurasi Firebase — skip tanpa error.
      return;
    }
    _initialized = true;

    // Registrasi handler untuk app terminated/background (data-only push).
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Batalkan subscription lama (jika init() pernah dipanggil ulang) agar
    // tidak ada listener ganda / memory leak.
    _messageSub?.cancel();
    _tokenRefreshSub?.cancel();
    _authSub?.cancel();

    _messageSub = FirebaseMessaging.onMessage.listen((message) {
      final d = message.data;
      final title = (d['title'] ?? message.notification?.title) as String?;
      final body = (d['body'] ?? message.notification?.body) as String?;
      if (title == null || body == null) return;
      // Jangan tampilkan jika chat dengan pengirim sedang terbuka.
      final senderId = d['sender_id'] as String?;
      if (senderId != null && senderId == PushService.activePeerId) return;
      PushService.show(title, body, senderId: senderId);
    });

    _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
      _currentToken = token;
      _syncToken(token);
    });

    // Sinkronkan token setiap kali user login.
    _authSub = maybeClient()?.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        _requestAndSync(messaging);
      } else if (data.event == AuthChangeEvent.signedOut) {
        _clearToken();
      }
    });

    await _requestAndSync(messaging);
  }

  /// Bersihkan semua subscription (dipanggil bila perlu reset service).
  static void dispose() {
    _messageSub?.cancel();
    _tokenRefreshSub?.cancel();
    _authSub?.cancel();
    _messageSub = null;
    _tokenRefreshSub = null;
    _authSub = null;
    _initialized = false;
  }

  static Future<void> _requestAndSync(
    FirebaseMessaging messaging,
  ) async {
    try {
      await messaging.requestPermission();
      final token = await messaging.getToken();
      _currentToken = token;
      await _syncToken(token);
    } catch (_) {}
  }

  static Future<void> _syncToken(String? token) async {
    final client = maybeClient();
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null || token == null || token.isEmpty) {
      return;
    }
    try {
      await client
          .from('private_profiles')
          .update({'device_token': token}).eq('id', uid);
    } catch (_) {}
  }

  static Future<void> _clearToken() async {
    final client = maybeClient();
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) return;
    try {
      await client.from('private_profiles').update({'device_token': null}).eq(
          'id', uid);
    } catch (_) {}
  }

  /// Dipanggil saat app resume dari background — kalau token sempat
  /// gagal tersinkron (mis. offline), coba lagi.
  static Future<void> resync() async {
    if (!_initialized || _currentToken == null) return;
    await _syncToken(_currentToken);
  }
}
