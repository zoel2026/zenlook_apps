# Setup Firebase Cloud Messaging (FCM) — Zenlook

Panduan untuk Verdi. Setelah selesai, kabari Edi supaya kode FCM-nya
dipasang ke aplikasi.

## Langkah (± 10 menit)

1. **Buka** https://console.firebase.google.com dan login pakai akun Google.
2. **Create project** (atau pakai existing):
   - Nama bebas, misal `zenlook`
   - Google Analytics: boleh dimatikan (tidak wajib).
3. Di dashboard project → ikon **Android** (atau Project Settings > Your apps > Add app > Android).
4. **Isi Android package name PERSIS seperti ini:**
   ```
   com.example.zenly_apps
   ```
   > ⚠️ Harus identik dengan `applicationId` di
   > `app/android/app/build.gradle.kts`. Kalau nanti package name diganti,
   > Firebase juga harus diganti.
5. **Register app** → **Download google-services.json**.
6. Kirim file `google-services.json` itu ke Edi / letakkan di:
   ```
   projects\app\android\app\google-services.json
   ```
7. Selesai bagian Firebase Console. Sisanya (gradle plugin, dependency,
   kode Dart, edge function) dikerjakan Edi.

## Yang akan Edi kerjakan setelahnya

- Pasang plugin `com.google.gms.google-services` di Gradle
- Tambah `firebase_core` + `firebase_messaging`
- Registrasi token FCM per device → simpan ke `profiles.device_token`
- Foreground: tampilkan notifikasi lokal saat ada pesan masuk
- Background/terminated: notifikasi dari FCM langsung
- Wire trigger DB → edge function `send-push`

## Catatan

- File `google-services.json` BUKAN secret (boleh masuk repo),
  tapi jangan sampai tertukar dengan private key service account.
- Service account key (`FIREBASE_SERVICE_ACCOUNT`) untuk edge function
  didapat dari: Project Settings > Service accounts > Generate new
  private key — INI YANG RAHASIA, kirim via env Supabase, bukan chat.
