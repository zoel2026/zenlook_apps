# Zenlook Feature Expansion — Task List

## Phase 1: Foundation (Database + Theme + Locale)

- [x] **Task 1**: Database Schema — tabel `blocked_users`, `message_reactions`, `user_reports` + kolom voice di `messages` + RLS
- [x] **Task 2**: Theme Provider — dark/light mode toggle dengan persistensi
- [x] **Task 3**: Locale Provider — multi language (ID/EN) dengan i18n

### Checkpoint 1: Foundation
- [ ] Database migration berhasil (perlu diterapkan ke Supabase)
- [x] Theme toggle berfungsi (dark ↔ light)
- [x] Locale toggle berfungsi (id ↔ en)

## Phase 2: Social Features (Block + Report + Typing)

- [x] **Task 4**: Block User — service + UI (block/unblock, filter dari chat & teman)
- [x] **Task 5**: Report User — service + dialog alasan + rate limit
- [x] **Task 6**: Typing Indicator — realtime broadcast + debounce + UI

### Checkpoint 2: Social Features
- [x] Block user berhasil (banner + RLS `is_blocked`)
- [x] Report user berhasil (data masuk ke tabel + rate limit 24 jam)
- [x] Typing indicator muncul real-time (channel broadcast + 5s auto-hide)

## Phase 3: Chat Enhancement (Reactions + Voice)

- [x] **Task 7**: Message Reactions — emoji picker + realtime update di bubble
- [x] **Task 8**: Voice Message — record, upload, play dengan progress bar

### Checkpoint 3: Chat Enhancement
- [x] Reactions muncul dan real-time (long-press bubble)
- [x] Voice message bisa direkam, dikirim, dan diputar (bucket `voice-messages`)
- [x] `flutter analyze` clean

## Phase 4: Location Features (Nearby Scan + Battery)

- [x] **Task 9**: Nearby Users Scan — RPC radius 2km + bottom sheet UI
- [x] **Task 10**: Battery Optimization — smart location (static/moving mode)

### Checkpoint 4: Location Features
- [ ] Nearby scan menampilkan user dalam radius 2km (butuh RPC di-deploy)
- [x] Battery mode aktif (interval + distance filter adaptif)
- [ ] Build apk release berhasil

## Phase 5: Notification Enhancement

- [x] **Task 11**: BBM-style Notifications — heads-up, quick reply, LED, custom sound

### Checkpoint 5: Complete
- [x] Semua 11 tugas selesai
- [x] `flutter analyze` clean
- [x] `flutter test` — 24 pass, 0 gagal (hijau per 2026-10-01; commit "Fix test environment initialization for map tab tests")
- [ ] Build release APK berhasil
- [ ] Ready for review

## Catatan Deploy yang Perlu Diterapkan
- [ ] Jalankan `backend/schema.sql` (canonical) di Supabase SQL Editor: tabel baru, RLS, RPC `get_nearby_users` + `haversine`, bucket `voice-messages` + policy
- [ ] Verifikasi `flutter pub get` (dependensi `record` + `audioplayers`)

## Phase 6: Audio Sharing & Background Player (MP3 di Chat)

- [x] **Task 12**: Schema & Bucket — kolom `is_audio`/`audio_url`/`audio_name`/`audio_duration` di `messages` + bucket `audio-files` (public read, upload owner-only) + `backend/schema.sql` (single source of truth)
- [x] **Task 13**: Upload & Kirim Pesan Audio — tombol attach (file_picker), validasi format (mp3/m4a/aac/wav) & ukuran (25 MB), insert message `is_audio` + i18n
- [x] **Task 14**: Player & Background Service — dependency `file_picker`/`just_audio`/`audio_service`, deklarasi service di AndroidManifest + permission, MediaService global + queue dari riwayat chat
- [x] **Task 15**: Bubble Audio di Chat — widget play/pause + progress + nama file/durasi, sinkronisasi voice player, auto-next antar lagu

### Checkpoint: Audio Sharing
- [x] Upload + kirim + tampil di bubble berfungsi (build APK debug sukses; runtime dengan device masih perlu uji manual)
- [ ] Playback berjalan di background dengan kontrol media (perlu uji manual di device: lock screen/notifikasi + app di background)
- [ ] Auto-next antar lagu berfungsi (perlu uji manual: pasang 2+ audio di chat, mainkan yang pertama)
- [x] `flutter analyze` clean
- [ ] Review dengan Bos

## Phase 7: Listening Indicator (Sedang Mendengarkan Music)

Referensi spec: `docs/SPEC-listening-status.md`

- [x] **Task 16**: `ListeningService` — broadcast realtime (on/off + nama lagu), dedupe, cleanup di dispose, fallback timeout
- [x] **Task 17**: Wiring di `ChatDetailScreen` — subscribe listen ke `gAudioService` (playbackState + mediaItem), emit broadcast play/stop, unsubscribe + reset di dispose
- [x] **Task 18**: UI indikator peer + i18n — tampil `"<name> sedang mendengarkan <judul>"` dengan ikon music saat peer listening; key `chat_listening_music` ID/EN

### Checkpoint: Listening Indicator
- [ ] Indikator "sedang mendengarkan <judul>" muncul real-time di layar chat lawan (perlu uji manual 2 device)
- [ ] Hilang saat pause/stop/tutup chat (perlu uji manual 2 device)
- [x] `flutter analyze` clean
- [ ] Review dengan Bos

## Phase 8: Wave — Ping "Di mana kamu?" 👋

Referensi spec: `docs/SPEC-wave.md`

- [x] **Task 19**: Backend — tabel `waves` + RLS (insert own ke teman accepted, select/delete involved) + cooldown 5 menit (trigger) + trigger push `notify_new_wave` (type `wave`) + realtime
- [x] **Task 20**: `wave_service.dart` — `sendWave()` + `watchIncoming()` realtime + `WaveResult` (pure mapper untuk test)
- [x] **Task 21**: UI — tombol 👋 di app bar chat + snackbar hasil; listener global di `HomeScreen` → `MessageBanner`
- [x] **Task 22**: i18n ID/EN (`wave`, `wave_sent`, `wave_cooldown`, `wave_blocked`, `wave_failed`, `wave_received_banner`, `wave_send_tooltip`)

### Checkpoint: Wave
- [x] `flutter analyze` clean
- [x] `flutter test` — 40 pass (termasuk `test/wave_service_test.dart`)
- [ ] Uji manual 2 akun: kirim wave, cooldown, push saat app tertutup (perlu deploy `backend/schema.sql`)
- [x] Entry point: tombol Wave di chat, daftar teman, dan panel monitoring peta
## Phase 9: Status & Aktivitas � " lagi ngapain?" dY`<

Referensi spec: `docs/SPEC-status.md`

- [x] **Task 23**: Backend dY" kolum `status_text`/`status_emoji`/`status_expires_at` di `profiles` + constraint panjang 60 karakter (idempotent, tanpa policy RLS baru)
- [x] **Task 24**: `status_service.dart` dY" `StatusTtl` + `isStatusActive()`/`activeStatusText()`/`statusLine()` (pure) + `setStatus()`/`clearStatus()`
- [x] **Task 25**: UI dY" kartu Status di `ProfileTab` (teks, pilihan emoji, masa berlaku 1/4/8 jam, Simpan & Hapus) + status teman di daftar teman dan panel monitoring peta
- [x] **Task 26**: i18n ID/EN (`status`, `status_placeholder`, `status_valid_for`, `status_expires_in`, `status_ttl_*`, `status_save`, `status_clear`, `status_saved`, `status_cleared`, `status_save_fail`)

### Checkpoint: Status & Aktivitas
- [x] `flutter analyze` clean
- [x] `flutter test` dY" 65 pass (termasuk `test/status_service_test.dart`)
- [ ] Terapkan `backend/schema.sql` di Supabase SQL Editor
- [ ] Uji manual: set status, terlihat di daftar teman, hangus setelah TTL

## Phase 10: Hapus Pesan (Delete for Me / Everyone)

Referensi spec: `docs/SPEC-delete-message.md`

- [x] **Task 27**: Backend dY" kolum `is_deleted`/`deleted_at`/`deleted_by` di `messages` + policy `messages_delete_own` + perluasan trigger `messages_update_guard` (allowlist kolom per role, tanpa undo)
- [x] **Task 28**: `message_service.dart` dY" `DeleteScope` (onlyMe/everyone), `mapDeleteErrorToResult()` (pure), `visibleMessageContent()` (pure), `deleteMessage()` dengan update dibatasi sender
- [x] **Task 29**: UI dY" `widgets/message_delete_button.dart` (tombol + sheet cakupan + konfirmasi), bubble menampilkan "Pesan ini dihapus" untuk teks/suara/audio yang terhapus, `is_deleted` masuk semua query select pesan
- [x] **Task 30**: i18n ID/EN (`message_deleted`, `delete_menu`, `delete_only_me`, `delete_for_everyone`, `delete_confirm_*`, `delete_ok`, `delete_not_allowed`, `delete_failed`)

### Checkpoint: Hapus Pesan
- [x] `flutter analyze` clean
- [x] `flutter test` dY" 77 pass (9 unit + 3 widget untuk fitur ini)
- [ ] Terapkan `backend/schema.sql` di Supabase SQL Editor
- [ ] Uji manual: hapus untuk semua (lawan melihat "Pesan ini dihapus"), hapus untuk saya, dan trigger menolak pemulihan
