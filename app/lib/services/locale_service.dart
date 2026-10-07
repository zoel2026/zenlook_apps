import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locale global — di-set saat app start.
LocaleController? gLocaleController;

enum AppLocale { id, en }

/// Controller bahasa aplikasi (Indonesia / English) dengan persistensi.
class LocaleController extends ValueNotifier<AppLocale> {
  LocaleController(super.locale);

  static const _prefKey = 'app_locale';

  static Future<LocaleController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    return LocaleController(
      stored == 'en' ? AppLocale.en : AppLocale.id,
    );
  }

  Future<void> setLocale(AppLocale locale) async {
    value = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, locale == AppLocale.en ? 'en' : 'id');
  }
}

/// Terjemahan sederhana berbasis map (tanpa dependency i18n tambahan).
class AppLocalizations {
  AppLocalizations(this._locale);

  final AppLocale _locale;

  static const _id = <String, String>{
    // Umum
    'search': 'Cari',
    'save': 'Simpan',
    'save_profile': 'Simpan Profil',
    'cancel': 'Batal',
    'send': 'Kirim',
    'close': 'Tutup',
    'delete': 'Hapus',
    'loading': 'Memuat...',
    'retry': 'Coba lagi',
    'back': 'Kembali',

    // Auth
    'select_language': 'Pilih bahasa',
    'welcome': 'Selamat Datang',
    'welcome_sub': 'Di Zenlook',
    'username': 'Username',
    'password': 'Password',
    'login': 'Masuk',
    'forgot_password': 'Lupa Password?',
    'no_username': 'Username wajib diisi',
    'username_min': 'Minimal 3 karakter',
    'password_required': 'Password wajib diisi',
    'no_connection': 'Tidak ada koneksi internet',
    'timeout': 'Koneksi timeout — coba lagi',
    'connect_error': 'Gagal terhubung',
    'wrong_credentials': 'Username atau password salah',
    'register': 'Daftar',
    'no_account': 'Belum punya akun? ',
    'create_account': 'Buat akun baru',
    'full_name': 'Nama Lengkap',
    'full_name_required': 'Nama lengkap wajib diisi',
    'email': 'Email',
    'email_not_valid': 'Email tidak valid',
    'phone_optional': 'No. HP (opsional)',
    'password_min': 'Minimal 6 karakter',
    'security_code': 'Kode Keamanan (6 digit)',
    'security_code_required': 'Kode keamanan wajib diisi',
    'security_code_format': 'Harus 6 digit angka',
    'security_code_hint':
        'Digunakan untuk reset password jika lupa',
    'register_success_email':
        'Pendaftaran berhasil! Cek email untuk verifikasi, lalu masuk dan atur security code di profil.',
    'register_success': 'Pendaftaran berhasil! Silakan masuk.',

    // Home
    'map': 'Peta',
    'friends': 'Teman',
    'chat': 'Chat',
    'profile': 'Profil',

    // Peta
    'realtime_map': 'Peta Real-time',
    'accuracy': 'Akurasi ±%s m',
    'permission_denied':
        'Izin lokasi ditolak. Aktifkan izin lokasi di pengaturan untuk fitur realtime.',
    'gps_off':
        'Lokasi (GPS) sedang mati. Nyalakan layanan lokasi perangkat agar posisi terkirim.',
    'map_tiles_not_configured':
        'Peta belum dikonfigurasi. Isi MAP_TILE_URL di .env agar tile tampil.',

    // Sembunyikan lokasi
    'hide_location': 'Sembunyikan lokasi saya',
    'show_location_to': 'Tampilkan lagi lokasi saya',
    'hide_location_confirm':
        'Teman ini tidak akan melihat lokasi Anda. Chat dan status tetap jalan.',
    'show_location_confirm': 'Teman ini akan melihat lokasi Anda lagi.',
    'location_hidden_badge': 'Lokasi disembunyikan',
    'manage_hidden_locations': 'Kelola lokasi tersembunyi',
    'hidden_locations_empty': 'Tidak ada teman yang disembunyikan',
    'hidden_locations_count': 'Lokasi disembunyikan dari %d teman',
    'location_visibility_ok': 'Pengaturan lokasi diperbarui',
    'location_visibility_not_allowed':
        'Tidak bisa mengubah visibility untuk teman ini',
    'location_visibility_invalid': 'Permintaan tidak valid',
    'location_visibility_failed': 'Gagal memperbarui pengaturan lokasi',

    // Status & Aktivitas
    'status': 'Status',
    'status_placeholder': 'Lagi ngapain?',
    'status_valid_for': 'Berlaku selama',
    'status_expires_in': 'Hangus dalam %d',
    'status_ttl_1h': '1 jam',
    'status_ttl_4h': '4 jam',
    'status_ttl_8h': '8 jam',
    'status_save': 'Simpan Status',
    'status_clear': 'Hapus Status',
    'status_saved': 'Status disimpan',
    'status_cleared': 'Status dihapus',
    'status_save_fail': 'Gagal menyimpan status',

    // Teman
    'search_friend': 'Cari nama atau username...',
    'no_result': 'Tidak ada hasil',
    'incoming_requests': 'Permintaan Masuk',
    'friend_list': 'Daftar Teman (%d)',
    'no_friends': 'Belum ada teman. Cari dan tambah teman di atas.',
    'delete_friend_tooltip': 'Hapus teman',
    'add': 'Tambah',
    'friendship_sent': 'Permintaan pertemanan terkirim',
    'friend_request_sent': 'friend request terkirim',
    'accept_request': 'Permintaan diterima',
    'reject_request': 'Permintaan ditolak',
    'cancel_request': 'Permintaan dibatalkan',
    'process_failed': 'Gagal memproses permintaan',
    'cancel_failed': 'Gagal membatalkan permintaan',
    'delete_friend_title': 'Hapus %s?',
    'delete_friend_body':
        'Kalian tidak akan bisa saling melihat lokasi lagi.',
    'delete_friend_success': '%s dihapus dari daftar teman',
    'delete_friend_failed': 'Gagal menghapus teman',
    'friend': 'Teman',
    'accept': 'Terima',
    'reject': 'Tolak',
    'waiting': 'Menunggu',
    'send_failed': 'Gagal mengirim permintaan',
    'search_failed': 'Gagal mencari teman',
    'interrupted': 'Batalkan',

    // Chat list
    'start_chat': 'Chat baru',
    'chat_no_conversation': 'Belum ada percakapan',
    'chat_hint': 'Tambah teman lalu kirim pesan',
    'choose_friend': 'Pilih teman',
    'no_friend_chat': 'Belum ada teman untuk diajak chat',
    'load_friends_fail': 'Gagal memuat daftar teman',
    'you': 'Anda',

    // Chat detail
    'chat_typing': 'sedang mengetik...',
    'wave': 'Wave',
    'wave_send_tooltip': 'Kirim wave 👋',
    'wave_sent': 'Wave terkirim 👋',
    'wave_cooldown': 'Sudah mengirim wave. Tunggu sebentar.',
    'wave_blocked': 'Tidak bisa mengirim wave ke pengguna ini',
    'wave_failed': 'Gagal mengirim wave',
    'wave_received_banner': '👋 minta lokasimu',
    'chat_listening_music': 'sedang mendengarkan %s',
    'music_mp3': 'music mp3',
    'message_hint': 'Tulis pesan...',
    'send_failed_msg': 'Gagal mengirim pesan',
    'mark_read': 'Tandai dibaca',

    // Music tab
    'music': 'Musik',
    'add_music': 'Tambah MP3',
    'no_music': 'Belum ada lagu. Ketuk + untuk pilih MP3.',
    'now_playing': 'Sedang diputar',
    'clear_queue': 'Bersihkan',
    'music_empty_queue': 'Antrean kosong',

    // Profil
    'edit_avatar_hint': 'Ketuk foto untuk ganti avatar',
    'upload_avatar_fail': 'Gagal upload foto',
    'profile_saved': 'Profil berhasil diperbarui',
    'profile_save_fail': 'Gagal menyimpan profil',
    'theme': 'Tema',
    'theme_system': 'System',
    'theme_light': 'Terang',
    'theme_dark': 'Gelap',
    'always_share': 'Bagikan lokasi selalu',
    'always_share_sub':
        'Tetap kirim posisi walau app di background. Butuh izin lokasi "selalu".',
    'always_share_on': 'Berbagi lokasi selalu: AKTIF',
    'always_share_off': 'Berbagi lokasi selalu: MATI',
    'always_share_denied':
        'Izin "lokasi selalu" tidak aktif. Aktifkan manual di pengaturan aplikasi.',
    'open_settings': 'Buka',
    'battery_saver': 'Mode Hemat Baterai',
    'battery_saver_sub':
        'Kirim lokasi lebih jarang saat diam untuk menghemat baterai.',
    'nearby_alert': 'Notifikasi user terdekat',
    'nearby_alert_sub':
        'Dapat notifikasi saat ada user lain masuk radius lokasi Anda. Privasi terjaga: hanya nama + jarak yang dikirim.',
    'nearby_alert_on': 'Notifikasi user terdekat: AKTIF',
    'nearby_alert_off': 'Notifikasi user terdekat: MATI',
    'nearby_radius': 'Radius deteksi',
    'nearby_radius_unit': 'm',
    'logout': 'Keluar',
    'logout_confirm_title': 'Keluar Aplikasi',
    'logout_confirm_body': 'Yakin ingin keluar dan menutup aplikasi?',
    'logout_yes': 'Keluar',

    // Forgot password
    'forgot_title': 'Lupa Password',
    'forgot_step1_title': 'Masukkan username',
    'forgot_step1_hint': 'Masukkan username akun Anda',
    'forgot_next': 'Lanjut',
    'forgot_user_not_found': 'Username tidak ditemukan',
    'forgot_step2_title': 'Verifikasi kode keamanan',
    'forgot_step2_hint':
        'Masukkan kode keamanan 6 digit yang dipakai saat mendaftar.',
    'forgot_verify': 'Verifikasi',
    'forgot_code_wrong': 'Kode keamanan salah atau kadaluarsa',
    'forgot_step3_title': 'Buat password baru',
    'forgot_new_pass': 'Password Baru',
    'forgot_confirm_pass': 'Konfirmasi Password',
    'forgot_mismatch': 'Konfirmasi tidak cocok',
    'forgot_done': 'Password berhasil direset. Silakan masuk.',
    'forgot_reset': 'Reset Password',
    'forgot_reset_success': 'Password berhasil diubah! Silakan masuk.',
    'verify_failed': 'Gagal memverifikasi data',
    'reset_failed': 'Gagal mengubah password',
    'verify_hint':
        'Masukkan username dan kode keamanan 6 digit\nyang dibuat saat pendaftaran.',
    'new_pass_hint': 'Buat password baru untuk akun kamaku.',
    'required': 'Wajib diisi',
    'back_to_login': 'Kembali ke Login',
    'too_many': 'Terlalu banyak percobaan. Coba lagi nanti.',
    'wrong_retry_15m': 'Coba lagi dalam 15 menit.',
    'forgot_new_pass_change': 'Ubah Password',

    // Block / Report
    'block_user': 'Blokir Pengguna',
    'unblock_user': 'Buka Blokir',
    'block_confirm_title': 'Blokir %s?',
    'block_confirm_body':
        'Kalian tidak akan bisa chat, melihat lokasi, atau mengirim permintaan pertemanan.',
    'block_success': 'Pengguna diblokir',
    'unblock_success': 'Blokir dibuka',
    'block_failed': 'Gagal memblokir pengguna',
    'unblock_failed': 'Gagal membuka blokir',
    'blocked_list': 'Daftar Blokir',
    'no_blocked': 'Belum ada pengguna diblokir',
    'report_user': 'Laporkan Pengguna',
    'report_reason_required': 'Pilih alasan laporan',
    'report_spam': 'Spam',
    'report_inappropriate': 'Konten tidak pantas',
    'report_harassment': 'Pelecehan',
    'report_fake_account': 'Akun palsu',
    'report_other': 'Lainnya',
    'report_confirm_title': 'Laporkan %s?',
    'report_confirm_body':
        'Laporan Anda akan diproses oleh tim kami. Terima kasih sudah menjaga komunitas tetap aman.',
    'report_success': 'Laporan terkirim. Terima kasih!',
    'report_failed': 'Gagal mengirim laporan',
    'report_already': 'Anda sudah melaporkan pengguna ini.',

    // Nearby scan
    'scan_nearby': 'Scan Sekitar',
    'nearby_users': 'Pengguna di Sekitar',
    'scan_radius_hint': 'Dalam radius %d km',
    'meters_away': '%d m',
    'km_away': '%.1f km',
    'no_nearby': 'Tidak ada pengguna di sekitar',
    'scan_too_soon': 'Tunggu sebentar sebelum scan lagi',
    'scan_failed': 'Gagal mencari pengguna di sekitar',
    'scan_notice':
        'Menampilkan pengguna Zenlook dalam radius %d km yang bukan teman Anda.',
    'premium_nearby_limit':
        'Free hanya bisa scan hingga %d km. Upgrade ke Pro untuk radius hingga %d km.',
    'premium_upgrade_cta': 'Tingkatkan ke Premium',
    'premium_pro_badge': 'Pro',
    'now': 'Sekarang',
    'just_now': 'Baru saja',
    'send_nearby_request': 'Kirim permintaan',
    'request_sent': 'Permintaan terkirim',

    // Voice message
    'voice_message': 'Pesan suara',
    'voice_release_send': 'Lepas untuk mengirim',
    'voice_slide_cancel': 'Geser untuk batal',
    'voice_recording': 'Merekam...',
    'voice_send_fail': 'Gagal mengirim pesan suara',
    'voice_perm_fail':
        'Izin mikrofon ditolak. Aktifkan di pengaturan.',

    // Hapus pesan
    'message_deleted': 'Pesan ini dihapus',
    'delete_menu': 'Hapus pesan',
    'delete_only_me': 'Hapus untuk saya',
    'delete_for_everyone': 'Hapus untuk semua orang',
    'delete_confirm_only_me':
        'Pesan ini akan hilang di daftar Anda, tapi masih terlihat oleh orang lain.',
    'delete_confirm_everyone':
        'Pesan ini akan dihapus untuk semua orang dan tidak bisa dipulihkan.',
    'delete_confirm_action': 'Hapus',
    'delete_ok': 'Pesan dihapus',
    'delete_not_allowed':
        'Pesan tidak bisa dihapus (bukan pesan Anda, atau sudah dihapus).',
    'delete_failed': 'Gagal menghapus pesan',

    // Audio message
    'audio_message': 'Audio',
    'audio_pick_fail': 'Gagal memilih file audio',
    'audio_invalid_format':
        'Format tidak didukung. Gunakan MP3, M4A, AAC, atau WAV.',
    'audio_too_large': 'Ukuran file maksimal 25 MB',
    'audio_send_fail': 'Gagal mengirim audio',

    // Premium
    // Sidebar / exit
    'sidebar_tagline': 'Bagikan lokasi bareng teman',
    'logout_app': 'Keluar Aplikasi',
    'exit_title': 'Keluar Aplikasi',
    'exit_body': 'Apakah anda yakin keluar aplikasi?',
    'yes': 'Ya',
    'no': 'Tidak',

    // Map monitoring panel
    'online': 'Online',
    'offline': 'Offline',
    'last_update': 'Terakhir update',
    'distance_from_you': 'Jarak dari kamu',
    'coordinates': 'Koordinat',
    'show_track': 'Tampilkan jalur',
    'hide_track': 'Sembunyikan jalur',
    'track_points': '%d titik',
    'secs_ago': '%ds lalu',
    'mins_ago': '%dm lalu',
    'menu': 'Menu',
    'never': 'belum pernah',
    'debug': 'Debug',
  };

  static const _en = <String, String>{
    'search': 'Search',
    'save': 'Save',
    'save_profile': 'Save Profile',
    'cancel': 'Cancel',
    'send': 'Send',
    'close': 'Close',
    'delete': 'Delete',
    'loading': 'Loading...',
    'retry': 'Retry',
    'back': 'Back',

    'select_language': 'Select language',
    'welcome': 'Welcome',
    'welcome_sub': 'To Zenlook',
    'username': 'Username',
    'password': 'Password',
    'login': 'Log In',
    'forgot_password': 'Forgot password?',
    'no_username': 'Username is required',
    'username_min': 'At least 3 characters',
    'password_required': 'Password is required',
    'no_connection': 'No internet connection',
    'timeout': 'Connection timeout — try again',
    'connect_error': 'Failed to connect',
    'wrong_credentials': 'Invalid username or password',
    'register': 'Register',
    'no_account': "Don't have an account? ",
    'create_account': 'Create new account',
    'full_name': 'Full Name',
    'full_name_required': 'Full name is required',
    'email': 'Email',
    'email_not_valid': 'Invalid email',
    'phone_optional': 'Phone (optional)',
    'password_min': 'At least 6 characters',
    'security_code': 'Security Code (6 digits)',
    'security_code_required': 'Security code is required',
    'security_code_format': 'Must be 6 digits',
    'security_code_hint': 'Used to reset password if forgotten',
    'register_success_email':
        'Registration successful! Check your email to verify, then log in and set your security code in profile.',
    'register_success': 'Registration successful! Please log in.',

    'map': 'Map',
    'friends': 'Friends',
    'chat': 'Chat',
    'profile': 'Profile',

    'realtime_map': 'Real-time Map',
    'accuracy': 'Accuracy ±%s m',
    'permission_denied':
        'Location permission denied. Enable location permission in settings for realtime features.',
    'gps_off':
        'Location (GPS) is off. Turn on device location to share your position.',
    'map_tiles_not_configured':
        'Map tiles are not configured. Set MAP_TILE_URL in .env to show tiles.',

    // Hide location
    'hide_location': 'Hide my location',
    'show_location_to': 'Show my location again',
    'hide_location_confirm':
        'This friend will not see your location. Chat and status still work.',
    'show_location_confirm': 'This friend will see your location again.',
    'location_hidden_badge': 'Location hidden',
    'manage_hidden_locations': 'Manage hidden locations',
    'hidden_locations_empty': 'No hidden friends',
    'hidden_locations_count': 'Location hidden from %d friends',
    'location_visibility_ok': 'Location setting updated',
    'location_visibility_not_allowed':
        'Cannot change visibility for this friend',
    'location_visibility_invalid': 'Invalid request',
    'location_visibility_failed': 'Failed to update location setting',

    // Status & activity
    'status': 'Status',
    'status_placeholder': 'What are you up to?',
    'status_valid_for': 'Valid for',
    'status_expires_in': 'Expires in %d',
    'status_ttl_1h': '1 hour',
    'status_ttl_4h': '4 hours',
    'status_ttl_8h': '8 hours',
    'status_save': 'Save Status',
    'status_clear': 'Clear Status',
    'status_saved': 'Status saved',
    'status_cleared': 'Status cleared',
    'status_save_fail': 'Failed to save status',

    'search_friend': 'Search name or username...',
    'no_result': 'No results',
    'incoming_requests': 'Incoming Requests',
    'friend_list': 'Friends (%d)',
    'no_friends': 'No friends yet. Search and add friends above.',
    'delete_friend_tooltip': 'Remove friend',
    'add': 'Add',
    'friendship_sent': 'Friend request sent',
    'friend_request_sent': 'Friend request sent',
    'accept_request': 'Request accepted',
    'reject_request': 'Request rejected',
    'cancel_request': 'Request canceled',
    'process_failed': 'Failed to process request',
    'cancel_failed': 'Failed to cancel request',
    'delete_friend_title': 'Remove %s?',
    'delete_friend_body': 'You will no longer see each other\'s location.',
    'delete_friend_success': '%s removed from friends',
    'delete_friend_failed': 'Failed to remove friend',
    'friend': 'Friend',
    'accept': 'Accept',
    'reject': 'Reject',
    'waiting': 'Waiting',
    'send_failed': 'Failed to send request',
    'search_failed': 'Failed to search friends',
    'interrupted': 'Cancel',

    'start_chat': 'New chat',
    'chat_no_conversation': 'No conversations yet',
    'chat_hint': 'Add friends then send a message',
    'choose_friend': 'Choose a friend',
    'no_friend_chat': 'No friends to chat with yet',
    'load_friends_fail': 'Failed to load friends',
    'you': 'You',

    'chat_typing': 'typing...',
    'wave': 'Wave',
    'wave_send_tooltip': 'Send a wave 👋',
    'wave_sent': 'Wave sent 👋',
    'wave_cooldown': 'Already waved. Wait a moment.',
    'wave_blocked': 'Cannot wave this user',
    'wave_failed': 'Failed to send wave',
    'wave_received_banner': '👋 wants your location',
    'chat_listening_music': 'is listening to %s',
    'music_mp3': 'music mp3',
    'message_hint': 'Type a message...',
    'send_failed_msg': 'Failed to send message',

    // Music tab
    'music': 'Music',
    'add_music': 'Add MP3',
    'no_music': 'No songs yet. Tap + to pick MP3 files.',
    'now_playing': 'Now playing',
    'clear_queue': 'Clear',
    'music_empty_queue': 'Queue is empty',

    'edit_avatar_hint': 'Tap photo to change avatar',
    'upload_avatar_fail': 'Failed to upload photo',
    'profile_saved': 'Profile updated',
    'profile_save_fail': 'Failed to save profile',
    'theme': 'Theme',
    'theme_system': 'System',
    'theme_light': 'Light',
    'theme_dark': 'Dark',
    'always_share': 'Always share location',
    'always_share_sub':
        'Keep sending your position even when the app is in background. Requires "always" location permission.',
    'always_share_on': 'Always share location: ON',
    'always_share_off': 'Always share location: OFF',
    'always_share_denied':
        '"Always location" permission is not active. Enable it manually in app settings.',
    'open_settings': 'Open',
    'battery_saver': 'Battery Saver',
    'battery_saver_sub':
        'Send location less often while idle to save battery.',
    'nearby_alert': 'Nearby user alerts',
    'nearby_alert_sub':
        'Get notified when another user enters your location radius. Privacy preserved: only name and distance are sent.',
    'nearby_alert_on': 'Nearby user alerts: ON',
    'nearby_alert_off': 'Nearby user alerts: OFF',
    'nearby_radius': 'Detection radius',
    'nearby_radius_unit': 'm',
    'logout': 'Log Out',
    'logout_confirm_title': 'Log Out',
    'logout_confirm_body': 'Are you sure you want to log out and close the app?',
    'logout_yes': 'Log Out',

    'forgot_title': 'Forgot Password',
    'forgot_step1_title': 'Enter username',
    'forgot_step1_hint': 'Enter your account username',
    'forgot_next': 'Next',
    'forgot_user_not_found': 'Username not found',
    'forgot_step2_title': 'Verify security code',
    'forgot_step2_hint':
        'Enter the 6-digit security code you set during registration.',
    'forgot_verify': 'Verify',
    'forgot_code_wrong': 'Security code is incorrect or expired',
    'forgot_step3_title': 'Create new password',
    'forgot_new_pass': 'New Password',
    'forgot_confirm_pass': 'Confirm Password',
    'forgot_mismatch': 'Confirmation does not match',
    'forgot_done': 'Password reset. Please log in.',
    'forgot_reset': 'Reset Password',
    'forgot_reset_success': 'Password changed successfully! Please log in.',
    'verify_failed': 'Failed to verify data',
    'reset_failed': 'Failed to change password',
    'verify_hint':
        'Enter your username and the 6-digit security code\nset during registration.',
    'new_pass_hint': 'Create a new password for your account.',
    'required': 'Required',
    'back_to_login': 'Back to Login',
    'too_many': 'Too many attempts. Try again later.',
    'wrong_retry_15m': 'Try again in 15 minutes.',
    'forgot_new_pass_change': 'Change Password',

    'block_user': 'Block User',
    'unblock_user': 'Unblock',
    'block_confirm_title': 'Block %s?',
    'block_confirm_body':
        'You will not be able to chat, see locations, or send friend requests.',
    'block_success': 'User blocked',
    'unblock_success': 'Block removed',
    'block_failed': 'Failed to block user',
    'unblock_failed': 'Failed to unblock user',
    'blocked_list': 'Blocked Users',
    'no_blocked': 'No blocked users',
    'report_user': 'Report User',
    'report_reason_required': 'Choose a report reason',
    'report_spam': 'Spam',
    'report_inappropriate': 'Inappropriate content',
    'report_harassment': 'Harassment',
    'report_fake_account': 'Fake account',
    'report_other': 'Other',
    'report_confirm_title': 'Report %s?',
    'report_confirm_body':
        'Your report will be processed by our team. Thank you for keeping the community safe.',
    'report_success': 'Report sent. Thank you!',
    'report_failed': 'Failed to send report',
    'report_already': 'You already reported this user.',

    'scan_nearby': 'Scan Nearby',
    'nearby_users': 'Nearby Users',
    'scan_radius_hint': 'Within %d km',
    'meters_away': '%d m',
    'km_away': '%.1f km',
    'no_nearby': 'No users nearby',
    'scan_too_soon': 'Wait a moment before scanning again',
    'scan_failed': 'Failed to find nearby users',
    'scan_notice':
        'Showing Zenlook users within %d km who are not your friends.',
    'now': 'Now',
    'just_now': 'Just now',
    'send_nearby_request': 'Send request',
    'request_sent': 'Request sent',

    'voice_message': 'Voice message',
    'voice_release_send': 'Release to send',
    'voice_slide_cancel': 'Slide to cancel',
    'voice_recording': 'Recording...',
    'voice_send_fail': 'Failed to send voice message',

    // Delete message
    'message_deleted': 'This message was deleted',
    'delete_menu': 'Delete message',
    'delete_only_me': 'Delete for me',
    'delete_for_everyone': 'Delete for everyone',
    'delete_confirm_only_me':
        'This message will disappear from your list, but the other person can still see it.',
    'delete_confirm_everyone':
        'This message will be deleted for everyone and cannot be restored.',
    'delete_confirm_action': 'Delete',
    'delete_ok': 'Message deleted',
    'delete_not_allowed':
        'Message cannot be deleted (not yours, or already deleted).',
    'delete_failed': 'Failed to delete message',
    'voice_perm_fail':
        'Microphone permission denied. Enable it in settings.',

    'audio_message': 'Audio',
    'audio_pick_fail': 'Failed to pick audio file',
    'audio_invalid_format':
        'Unsupported format. Use MP3, M4A, AAC, or WAV.',
    'audio_too_large': 'File size max is 25 MB',
    'audio_send_fail': 'Failed to send audio',

    'sidebar_tagline': 'Share location with friends',
    'logout_app': 'Log Out App',
    'exit_title': 'Exit App',
    'exit_body': 'Are you sure you want to exit the app?',
    'yes': 'Yes',
    'no': 'No',
    'online': 'Online',
    'offline': 'Offline',
    'last_update': 'Last update',
    'distance_from_you': 'Distance from you',
    'coordinates': 'Coordinates',
    'show_track': 'Show track',
    'hide_track': 'Hide track',
    'track_points': '%d points',
    'secs_ago': '%ds ago',
    'mins_ago': '%dm ago',
    'menu': 'Menu',
    'never': 'never',
    'debug': 'Debug',
  };

  static AppLocalizations of(BuildContext context) {
    final locale = gLocaleController?.value ?? AppLocale.id;
    return AppLocalizations(locale);
  }

  /// Ambil terjemahan. Mendukung placeholder %s / %d / %.1f berurutan.
  String t(String key, {List<Object>? args}) {
    final table = _locale == AppLocale.en ? _en : _id;
    var s = table[key] ?? _en[key] ?? key;
    final a = args;
    if (a != null && a.isNotEmpty) {
      var i = 0;
      s = s.replaceAllMapped(RegExp(r'%\.1f|%[sd]'), (m) {
        if (i >= a.length) return m.group(0)!;
        return a[i++].toString();
      });
    }
    return s;
  }
}

extension L10nContext on BuildContext {
  AppLocalizations get l => AppLocalizations.of(this);
}
