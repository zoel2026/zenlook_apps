# Notifikasi Push (Zenly Apps)

App sudah punya **notifikasi lokal** yang aktif tanpa konfigurasi apa pun:
- Pesan chat baru → muncul notifikasi (nama pengirim + isi pesan), walau user sedang di tab lain (Peta/Teman/Profil).
- Diimplementasikan lewat `flutter_local_notifications` di `lib/services/push_service.dart` + callback realtime di `lib/screens/chat_tab.dart`.

## Cara kerja sekarang (lokal, tanpa server)

1. `PushService.init()` dipanggil di `main()` → minta izin notifikasi (Android 13+).
2. Saat ada insert pesan masuk di tabel `messages` (realtime), `ChatTabState._notifyIncoming()` menampilkan notifikasi.
3. Kelemahan: hanya bekerja **saat app terbuka** (realtime butuh koneksi aktif). Untuk notifikasi saat app tertutup / dari server, perlu FCM di bawah.

## Upgrade ke push sungguhan (Firebase Cloud Messaging)

Arsitektur yang disarankan: FCM + Supabase Edge Function.

### 1. Buat project Firebase
- https://console.firebase.google.com → Add project → tambahkan Android app dengan package `com.example.zenly_apps`.
- Unduh `google-services.json` → letakkan di `android/app/`.
- Buat **service account key**: Project settings → Service accounts → Generate new private key → simpan JSON-nya sebagai secret Edge Function bernama `FIREBASE_SERVICE_ACCOUNT`.

> ⚠️ Legacy server key / API lama (`fcm.googleapis.com/fcm/send`) sudah dimatikan Google sejak Juni 2024. Gunakan HTTP v1 seperti pada kode saat ini.

### 2. Simpan token perangkat
Tambahkan baris ini di `lib/services/push_service.dart` setelah `init()`:
```dart
import 'package:firebase_messaging/firebase_messaging.dart';
final token = await FirebaseMessaging.instance.getToken();
if (token != null) {
  await supabase.from('profiles').update({'device_token': token}).eq('id', userId);
}
```
Kolom `device_token` sudah ada di tabel `profiles` (lihat `schema.sql`).

### 3. Deploy Edge Function
Simpan service account JSON sebagai secret, lalu deploy:
```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
cd backend/functions/send-push
supabase functions deploy send-push
```

Contoh kode ada di `backend/functions/send-push/index.ts`. Trigger dari aplikasi lain (misal saat ada pesan baru) lewat RPC/HTTP call dengan body:
```json
{ "userId": "<uuid>", "title": "Pesan baru", "body": "Budi: halo" }
```

### 4. Tambah dependency Firebase
```bash
flutter pub add firebase_messaging firebase_core
```
Lalu sambungkan di `main.dart` (init Firebase sebelum Supabase). Setelah `google-services.json` ada, jalankan ulang build.

> Catatan: `firebase_messaging` butuh `google-services.json` agar build berhasil — itulah kenapa default project ini memakai `flutter_local_notifications` (build tetap jalan tanpa Firebase).
