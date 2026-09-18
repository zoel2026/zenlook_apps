import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/supabase_guard.dart';

/// Menampilkan notifikasi gaya BBM: muncul di atas (heads-up), LED biru,
/// getar, kategori pesan, dan Quick Reply langsung dari notifikasi.
class PushService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static int _lastId = 0;

  /// Dedupe notifikasi: ketika FCM aktif, satu pesan masuk bisa dipicu
  /// dua kali (onMessage FCM + realtime ChatTab). Jendela 5 detik cukup
  /// untuk menangkap duplikat dari pesan yang sama.
  static String? _lastShownKey;
  static DateTime? _lastShownAt;

  /// Id peer yang chat-nya sedang terbuka di layar.
  /// Dipakai untuk menekan notifikasi lokal yang tidak perlu.
  static String? activePeerId;

  static bool _wasJustShown(String title, String body, String? senderId) {
    final now = DateTime.now();
    final key = '${senderId ?? ''}\u0000$title\u0000$body';
    if (key == _lastShownKey &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(seconds: 5)) {
      return true;
    }
    _lastShownKey = key;
    _lastShownAt = now;
    return false;
  }

  static Future<void> init() async {
    if (_initialized) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _initialized = true;
    } catch (_) {
      // Init gagal — biarkan _initialized false agar retry memungkinkan.
    }
  }

  static int _nextId() => ++_lastId;

  /// Tampilkan notifikasi chat.
  ///
  /// [senderId] dipakai untuk Quick Reply: balasan langsung terkirim ke
  /// pengguna pengirim tanpa membuka aplikasi.
  static Future<void> show(
    String title,
    String body, {
    String? senderId,
  }) async {
    await init();
    // Skip duplikat (FCM + realtime memicu dua kali untuk pesan sama).
    if (_wasJustShown(title, body, senderId)) return;
    try {
      final android = AndroidNotificationDetails(
        'chat',
        'Chat',
        channelDescription: 'Notifikasi pesan chat',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.private,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 300, 120, 300, 120, 400]),
        enableLights: true,
        ledOnMs: 800,
        ledOffMs: 400,
        actions: senderId == null
            ? null
            : [
                AndroidNotificationAction(
                  'reply',
                  'Balas',
                  showsUserInterface: false,
                  cancelNotification: false,
                  allowGeneratedReplies: true,
                  inputs: [
                    const AndroidNotificationActionInput(
                      label: 'Balas pesan...',
                    ),
                  ],
                ),
              ],
      );
      final details = NotificationDetails(android: android);
      await _plugin.show(_nextId(), title, body, details, payload: senderId);
    } catch (_) {}
  }

  static void _onNotificationResponse(NotificationResponse response) async {
    if (response.actionId == null) return;
    if (response.actionId == 'reply') {
      final peerId = response.payload;
      final text = response.input?.trim();
      final client = maybeClient();
      final me = client?.auth.currentUser?.id;
      if (client == null || me == null || peerId == null || text == null) {
        return;
      }
      if (text.isEmpty) return;
      try {
        await client.from('messages').insert({
          'sender_id': me,
          'receiver_id': peerId,
          'content': text,
        });
      } catch (_) {}
    }
  }
}