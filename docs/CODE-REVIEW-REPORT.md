# Code Review Report — Zenlook Apps

Tanggal: 2026-09-14
Ruang lingkup: `app/` (Flutter), `backend/` (Supabase schema + Edge Functions), `schema.sql`.

## Verifikasi

| Check | Hasil |
|-------|-------|
| `flutter analyze` | ✅ No issues found |
| `flutter test` | ❌ 4/10 lulus, 6 gagal |

---

## CRITICAL (blokir / harus diperbaiki)

### C1. Edge Function `reset-password` — insecure DAN rusak
File: `backend/supabase/functions/reset-password/index.ts`

- Endpoint publik tanpa autentikasi, CORS `Access-Control-Allow-Origin: *`, memakai **service_role key**.
- **Rusak:** verifikasi kode pakai `.eq("security_code", security_code)` (perbandingan plaintext), padahal `security_code` sudah disimpan sebagai **hash bcrypt** sejak fix 2026-08-31 → selalu gagal.
- Tidak ada rate limiting (bandingkan dengan RPC `reset_password_with_code` yang sudah rate-limited + bcrypt).
- Flow lupa password di Flutter sudah memakai RPC, bukan fungsi ini.

**Tindakan:** hapus fungsi ini (dead code + liability), atau jika tetap dipakai, call RPC `reset_password_with_code` via service role dan tambah internal key seperti `send-push`.

### C2. Canonical `schema.sql` kehilangan policy SELECT `location_history`
File: `backend/schema.sql`

- Komentar baris 941 menyebut "owner can read own + friends can read", **tapi tidak ada** policy SELECT dibuat.
- Policy `location_history_select_own` / `location_history_select_friends` hanya ada di `backend/sql/_archive/2026-08-22_fix_location_monitoring.sql`.
- Database baru dari `schema.sql` mentah → fitur **jalur pergerakan (movement track)** di `MapTab._loadTrack` gagal diam-diam (RLS deny).

**Tindakan:** salin kedua policy + grant `select` ke dalam `schema.sql`.

### C3. Canonical `schema.sql` kehilangan trigger notifikasi push
- Trigger `notify_new_message` (pg_net → edge function `send-push`) hanya ada di `_archive/2026-08-23_privacy_hardening.sql` dan `2026-08-23_message_push_trigger.sql`.
- README menyatakan push notification adalah fitur utama, tapi DB baru dari `schema.sql` tidak akan mengirim push sama sekali.

**Tindakan:** masukkan trigger + dependency (pg_net, `app_secrets`, `push_internal_key`) ke `schema.sql`.

### C4. Policy upload bucket `voice-messages` tanpa pembatasan pemilik
File: `backend/schema.sql` baris 205-209

- `voice_messages_auth_upload` hanya cek `bucket_id = 'voice-messages'` — **tidak** membatasi folder milik sender seperti `audio-files` dan `avatars`.
- Artinya user terautentikasi bisa meng-upload/overwrite path milik user lain, atau spam file bebas di bucket.
- Inkonsisten dengan pola lain (`auth.uid()::text = (storage.foldername(name))[1]`).

**Tindakan:** tambahkan cek prefix `auth.uid()` pada policy insert (dan tambahkan policy delete/update owner).

---

## REQUIRED (harus ditangani)

### R1. `MapTab` crash kalau Supabase belum diinisialisasi + bikin test gagal
File: `app/lib/screens/map_tab.dart:53`

```dart
String? get _myId => supabase.auth.currentUser?.id; // dipakai di build()
```

- Getter ini memakai `Supabase.instance.client` secara langsung (tidak lewat `maybeClient()` seperti FriendsTab/ChatTab/ProfileTab).
- Saat `build()` dieksekusi tanpa Supabase terinisialisasi → assertion `You must initialize the supabase instance` → semua `home_test.dart` gagal (IndexedStack mem-build keempat tab sekaligus).

**Tindakan:** ganti dengan guard `maybeClient()`, lalu perbaiki/rapikan test.

### R2. Test `widget_validation_test.dart` sudah ketinggalan zaman
- Test masih mengasumsikan login berbasis email (`Email`, `Email wajib diisi`, `Email tidak valid`) — padahal login sudah di-migrasi ke **username** (2026-08-26).
- Test gagal sebelum menyentuh validasi (`find.widgetWithText(TextFormField, 'Email')` menemukan 0 widget).
- Perlu update: login → form Username + Password (validasi `Username wajib diisi`, `Password wajib diisi`), register → validasi yang sesuai.

### R3. Ketidakcocokan project Supabase antara app dan backend
- `app/.env` → `https://pxifrxnkqxgzcgopgtvm.supabase.co`
- `backend/README.md` + URL hardcoded di SQL trigger → `https://ytmkhmsndfwmjlfyxiiw.supabase.co`

Salah satu pasti salah. Kalau app menunjuk project yang berbeda dari kolom RLS/schema yang di-deploy, sebagian fitur akan rusak runtime.

### R4. Struktur folder Edge Function terduplikasi
- `backend/functions/send-push/index.ts` (identik dengan di bawah, hash sama)
- `backend/supabase/functions/send-push/index.ts`
- `backend/supabase/functions/reset-password/index.ts`

`supabase functions deploy` ambigu (dua lokasi). Rapikan jadi satu root: `backend/supabase/functions/`.

---

## OPTIONAL / CONSIDER

- **Chat list `limit(500)`** (`chat_tab.dart:76`) — percakapan yang lebih lama dari 500 pesan terbaru hilang dari list. Komen di kode sudah mencatat "solusi proper: RPC di database". Jadikan task nyata.
- **Hardcoded anon key di SQL** (`_archive/2026-08-23_privacy_hardening.sql:174`) — dipakai trigger push. Bila anon key di-rotate, push diam-diam mati. Sebaiknya dibaca dari env/`app_secrets`, atau minimal diberi tanda.
- **`VoiceMessageBubble` membuat 1 `AudioPlayer` per bubble** (`voice_message_bubble.dart:41`) — banyak player aktif sekaligus; untuk 40 pesan suara di layar jadi 40 player. Pertimbangkan satu shared player.
- **Precheck internet via DNS** (`login_screen.dart:32`, `InternetAddress.lookup`) menambah latensi tiap login; kadang false-negative kalau DNS di-block. Pertimbangkan timeout + fallback langsung ke request.
- **`get_email_by_username`/`get_user_id_by_username` di-grant ke `anon`** — by design untuk login/lupa password, tapi bisa dipakai enumerasi username→email. Sudah di-rate-limit sebagian; nilai apakah perlu `anon` untuk `get_user_id_by_username` (tidak benar-benar terpakai app).
- **Dua versi trigger push di archive** (`message_push_trigger.sql` vs `privacy_hardening.sql`) — yang di `privacy_hardening` lebih baru (pakai `app_secrets`); buang versi lama agar tidak membingungkan saat meng-copy SQL.

---

## DEAD CODE / DUPLIKAT

- `backend/supabase/functions/reset-password/index.ts` — rusak + superseded by RPC (lihat C1).
- `backend/functions/send-push/` — duplikat dari `backend/supabase/functions/send-push/`.
- `widget_validation_test.dart` — assertion login email yang tak lagi relevan (perlu ditulis ulang, bukan dihapus).
- Beberapa `DROP policy if exists` + `create` di archive yang sudah masuk `schema.sql` — aman dipertahankan sebagai riwayat, tapi jangan dijadikan sumber kebenaran.

---

## Verdict

**Request changes.** Inti: sinkronisasi `schema.sql` (3 gap C2/C3/C4), hapus/perbaiki `reset-password` edge function (C1), guard `MapTab` + kembalikan test ke hijau (R1/R2), verifikasi project ref (R3).

---

# Fix Log — 2026-09-16 (review kedua + perbaikan)

## Backend (backend/schema.sql + hapus file)

| Item | Status |
|---|---|
| bcrypt cost 12 di `handle_new_user` + `set_security_code` (sebelumnya cost 6) | ✅ Fixed |
| Guard `security_code` langsung dari client — trigger `private_profiles_update_guard` (hanya service_role/SECURITY DEFINER boleh; NC-1 lama) | ✅ Fixed |
| Cabut grant `anon` dari `get_user_id_by_username` (tidak dipakai app; anti enumerasi) | ✅ Fixed |
| C2: policy SELECT `location_history` (own + friends + block-aware) masuk schema | ✅ Fixed |
| C4: upload `voice-messages` kini butuh prefix `uploads/<auth.uid()>_` | ✅ Fixed |
| Storage: policy UPDATE/DELETE owner untuk `voice-messages` + `audio-files` | ✅ Fixed |
| C3: `pg_net` + `notify_new_message` + trigger `messages_notify_push` masuk schema; body push dipangkas 80 char (privacy), tanpa secret hardcode | ✅ Fixed |
| `app_secrets` kini RLS-aktif; `push_internal_key` WAJIB diset per-env (tidak dikomit lagi) | ⏳ WAJIB diset di dashboard + env Edge Function |
| C1: `reset-password` edge function (insecure) | ✅ DIHAPUS |
| R4: folder duplikat `backend/functions/` | ✅ DIHAPUS (satu root: `supabase/functions/`) |

## Flutter (app/lib)

| Item | Status |
|---|---|
| R1: `MapTab._myId` tak lagi menyentuh `Supabase.instance` langsung (pakai `maybeClient()`) | ✅ Fixed |
| Privacy lock-screen: notifikasi chat → `NotificationVisibility.private` | ✅ Fixed |
| `flutter analyze` | ✅ No issues found |

## Tindak lanjut yang masih WAJIB manual (di dashboard Vercel/Supabase)

1. **Rotasi `push_internal_key`** — key lama ter-commit di `backend/sql/_archive/`; generate nilai acak baru, set sebagai `app_secrets.push_internal_key` DAN env `PUSH_INTERNAL_KEY` di Edge Function `send-push` (nilai sama).
2. **Resolusi project ref (R3)** — `app/.env` = `pxifrxnkqxgzcgopgtvm` vs `backend/README` + `notify_new_message` = `ytmkhmsndfwmjlfyxiiw`. Tentukan SATU project; sesuaikan URL trigger.
3. **Deploy perubahan schema** ke project via `supabase db push` / SQL Editor (hati-hati: `create extension pg_net` butuh izin; verifikasi dulu di staging).
4. Rate limit `get_email_by_username` per-IP (penyempurnaan NC-3; belum diterapkan).
5. `security_code` plaintext masih bisa lewat `auth.users.raw_user_meta_data` saat signup — pindahkan set kode via RPC `set_security_code` setelah login (NR-1).

## Catatan desain (belum dikerjakan, prioritas menengah)

- `location_history` tanpa retensi (usulkan pg_cron hapus >30 hari).
- `get_nearby_users` full-scan; tambah index `locations(updated_at desc)` + prefilter bbox.
- Split `chat_detail_screen.dart` (1104 baris) & `schema.sql` (1159 baris).
- Voice player per-bubble (1 AudioPlayer/bubble) — migrasi ke satu shared player.