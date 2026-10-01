# Implementation Plan: Zenlook Feature Expansion

## Overview
Menambahkan 10 fitur baru ke aplikasi Zenlook (social map app). Fitur meliputi: typing indicator, block user, scan user dalam radius 2km, message reactions, voice message, battery optimization, dark/light theme, multi-language, report user, dan notifikasi gaya BBM.

## Architecture Decisions

### State Management
- Tetap pakai `setState` + `StreamBuilder` (konsisten dengan kode yang ada)
- Theme & locale: gunakan `ValueNotifier` + `InheritedWidget` pattern (ringan, tanpa dependency baru)

### Database Changes
- Tabel baru: `blocked_users`, `message_reactions`, `user_reports`
- Kolom baru: `messages.is_voice`, `messages.voice_url`, `messages.voice_duration`
- RPC baru: `get_nearby_users`, `check_typing`

### Realtime Channels
- Typing indicator via Supabase Realtime broadcast (bukan postgres changes)
- Reaksi pesan via postgres changes pada tabel `message_reactions`

### File Organization
- Fitur baru ditambahkan ke structure yang ada (screens/, services/, widgets/)
- Tidak refactor besar-besaran — inkremental

## Dependency Graph

```
Database Schema (blocked_users, message_reactions, user_reports, voice columns)
    │
    ├── Theme Provider (independent, bisa duluan)
    │
    ├── Locale Provider (independent, bisa duluan)
    │
    ├── Block User Service + UI
    │
    ├── Typing Indicator (Realtime broadcast)
    │
    ├── Message Reactions (DB + Realtime)
    │
    ├── Voice Message (record + upload + play)
    │
    ├── Nearby Users Scan (RPC + UI)
    │
    ├── Battery Optimization (smart location)
    │
    ├── Report User (DB + UI)
    │
    └── BBM-style Notifications (enhanced local notif)
```

## Task List

### Phase 1: Foundation (Database + Theme + Locale)

#### Task 1: Database Schema — New Tables & Columns
**Description:** Buat tabel `blocked_users`, `message_reactions`, `user_reports`. Tambah kolom voice di `messages`. Setup RLS policies.
**Acceptance criteria:**
- [ ] Tabel `blocked_users` dengan RLS (user_id, blocked_id, created_at)
- [ ] Tabel `message_reactions` dengan RLS (message_id, user_id, emoji)
- [ ] Tabel `user_reports` dengan RLS (reporter_id, reported_id, reason, created_at)
- [ ] Kolom `is_voice`, `voice_url`, `voice_duration` di `messages`
- [ ] Index untuk performa
- [ ] Realtime enabled untuk `message_reactions`
**Files:** `backend/schema.sql`
**Estimated scope:** M (2-3 files)

#### Task 2: Theme Provider — Dark/Light Mode
**Description:** Buat `ThemeController` dengan `ValueNotifier<ThemeMode>`. Persistensi tema ke `shared_preferences`. Update `MaterialApp` untuk pakai theme controller.
**Acceptance criteria:**
- [ ] `ThemeController` singleton dengan `ValueNotifier<ThemeMode>`
- [ ] Persistensi tema (dark/light/system) ke SharedPreferences
- [ ] Toggle di ProfileTab
- [ ] Semua screen mengikuti tema (light mode colors defined)
- [ ] System theme detection
**Files:** `app/lib/services/theme_service.dart`, `app/lib/main.dart`, `app/lib/screens/profile_tab.dart`
**Estimated scope:** S (2-3 files)

#### Task 3: Locale Provider — Multi Language
**Description:** Buat sistem i18n sederhana dengan `AppLocalizations`. Map string keys ke text Indonesia/English. Persistensi bahasa.
**Acceptance criteria:**
- [ ] `AppLocalizations` class dengan `static of(context)` pattern
- [ ] File `assets/lang/id.json` dan `assets/lang/en.json`
- [ ] Semua string hardcoded di UI diganti dengan `AppLocalizations.of(context).key`
- [ ] Toggle bahasa di ProfileTab
- [ ] Persistensi bahasa pilihan
**Files:** `app/lib/services/locale_service.dart`, `app/lib/screens/profile_tab.dart`, `assets/lang/*.json`
**Estimated scope:** L (5+ files)

### Checkpoint 1: Foundation
- [ ] Database migration berhasil dijalankan
- [ ] Theme toggle berfungsi (dark ↔ light)
- [ ] Locale toggle berfungsi (id ↔ en)

---

### Phase 2: Social Features (Block + Report + Typing)

#### Task 4: Block User — Service & UI
**Description:** Implementasi block/unblock user. User yang di-block tidak bisa: chat, melihat lokasi, mengirim friend request.
**Acceptance criteria:**
- [ ] `BlockService` dengan `blockUser()`, `unblockUser()`, `isBlocked()`, `getBlockedUsers()`
- [ ] Tombol "Block" di ChatDetailScreen dan ProfileSheet
- [ ] Dialog konfirmasi block
- [ ] Filter blocked users dari daftar teman & chat
- [ ] RLS policy: blocked user tidak bisa insert message
**Files:** `app/lib/services/block_service.dart`, `app/lib/screens/chat_detail_screen.dart`, `app/lib/screens/friends_tab.dart`, `backend/schema.sql`
**Estimated scope:** M (3-4 files)

#### Task 5: Report User — Service & UI
**Description:** Laporkan pengguna dengan alasan (spam, inappropriate, harassment, other). Ada rate limit 1 report per target per 24 jam.
**Acceptance criteria:**
- [ ] `ReportService` dengan `reportUser()`, `hasReported()`
- [ ] Dialog pilih alasan report
- [ ] Tombol "Report" di ChatDetailScreen dan ProfileSheet
- [ ] Rate limit: 1 report per reporter+target per 24 jam
- [ ] Snackbar konfirmasi
**Files:** `app/lib/services/report_service.dart`, `app/lib/screens/chat_detail_screen.dart`, `app/lib/widgets/report_dialog.dart`
**Estimated scope:** S (2-3 files)

#### Task 6: Typing Indicator — Realtime Broadcast
**Description:** Tampilkan indikator "sedang mengetik..." saat peer mengetik di chat. Pakai Supabase Realtime broadcast (bukan postgres changes) untuk efisiensi.
**Acceptance criteria:**
- [ ] Broadcast typing event via `supabase.channel('typing_$peerId')`
- [ ] Debounce: kirim typing event max sekali per 2 detik
- [ ] Tampilkan "sedang mengetik..." di ChatDetailScreen (animated dots)
- [ ] Auto-hide setelah 5 detik tanpa activity
- [ ] Tidak kirim typing event jika chat tidak active
**Files:** `app/lib/services/typing_service.dart`, `app/lib/screens/chat_detail_screen.dart`
**Estimated scope:** S (2 files)

### Checkpoint 2: Social Features
- [ ] Block user berhasil — pesan tidak masuk, lokasi tidak terlihat
- [ ] Report user berhasil — data masuk ke tabel
- [ ] Typing indicator muncul real-time di chat

---

### Phase 3: Chat Enhancement (Reactions + Voice)

#### Task 7: Message Reactions — DB & UI
**Description:** React pesan dengan emoji (👍 ❤️ 😂 😮 😢 😡). Tampilkan di bubble chat. Realtime update.
**Acceptance criteria:**
- [ ] Long-press bubble → muncul emoji picker (6 emoji)
- [ ] Tampilkan reaction count di bawah bubble
- [ ] User bisa toggle reaction (tap lagi untuk unreact)
- [ ] Realtime update via postgres changes
- [ ] Animasi muncul saat reaction ditambahkan
**Files:** `app/lib/screens/chat_detail_screen.dart`, `app/lib/widgets/message_reactions.dart`, `backend/schema.sql`
**Estimated scope:** M (3 files)

#### Task 8: Voice Message — Record & Play
**Description:** Rekam pesan suara (max 60 detik), upload ke Supabase Storage, kirim sebagai message type `is_voice`. Play audio di chat.
**Acceptance criteria:**
- [ ] Tombol mic di chat input (hold to record)
- [ ] Visual waveform saat recording
- [ ] Upload audio ke Supabase Storage bucket `voice-messages`
- [ ] Simpan metadata: `is_voice=true`, `voice_url`, `voice_duration`
- [ ] Play/pause button di bubble voice message
- [ ] Progress bar saat play
- [ ] Max duration 60 detik, auto-stop
**Files:** `app/lib/services/voice_service.dart`, `app/lib/screens/chat_detail_screen.dart`, `app/lib/widgets/voice_message_bubble.dart`
**Estimated scope:** L (4-5 files)

### Checkpoint 3: Chat Enhancement
- [ ] Reactions muncul dan update real-time
- [ ] Voice message bisa direkam, dikirim, dan diputar
- [ ] `flutter analyze` clean

---

### Phase 4: Location Features (Nearby Scan + Battery)

#### Task 9: Nearby Users Scan — RPC & UI
**Description:** Cari user dalam radius 2km dari posisi saat ini. Tampilkan di sheet dengan info jarak.
**Acceptance criteria:**
- [ ] RPC `get_nearby_users(p_lat, p_lng, p_radius_km)` mengembalikan user dalam radius
- [ ] Hanya tampilkan user yang bukan teman dan belum di-block
- [ ] UI: tombol "Scan" di MapTab → bottom sheet daftar nearby users
- [ ] Tampilkan jarak (m/km), username, avatar
- [ ] Tombol "Tambah Teman" langsung dari hasil scan
- [ ] Rate limit: max 1 scan per 30 detik
**Files:** `backend/schema.sql` (RPC), `app/lib/screens/map_tab.dart`, `app/lib/widgets/nearby_users_sheet.dart`
**Estimated scope:** M (3-4 files)

#### Task 10: Battery Optimization — Smart Location
**Description:** Optimasi pengiriman lokasi berdasarkan gerakan. Jika diam (accuracy stabil), kurangi frequency. Jika bergerak, tingkatkan.
**Acceptance criteria:**
- [ ] Deteksi statis vs bergerak (delta lat/lng < threshold)
- [ ] Static mode: kirim lokasi setiap 30 detik
- [ ] Moving mode: kirim lokasi setiap 5 detik (atau distanceFilter 10m)
- [ ] Toggle "Battery Saver Mode" di ProfileTab
- [ ] Log perubahan mode di debug panel
**Files:** `app/lib/services/location_service.dart`, `app/lib/services/map_location_manager.dart`, `app/lib/screens/profile_tab.dart`
**Estimated scope:** S (2-3 files)

### Checkpoint 4: Location Features
- [ ] Nearby scan menampilkan user dalam radius 2km
- [ ] Battery mode aktif — lokasi dikirim lebih jarang saat diam
- [ ] Build apk release berhasil

---

### Phase 5: Notification Enhancement

#### Task 11: BBM-style Notifications — Enhanced Local Notif
**Description:** Notifikasi dengan gaya BBM: LED blink, custom sound, vibration pattern, heads-up notification, quick reply.
**Acceptance criteria:**
- [ ] Custom notification channel untuk chat (penting)
- [ ] Heads-up notification (muncul di atas layar)
- [ ] Quick reply langsung dari notifikasi
- [ ] Custom sound (vibrate + ding)
- [ ] LED color (Android)
- [ ] Tampilkan avatar sender di notifikasi (big picture style)
- [ ] Notifikasi mention di group (untuk future group chat)
**Files:** `app/lib/services/push_service.dart`, `app/lib/services/fcm_service.dart`, `app/lib/utils/notification_helper.dart`
**Estimated scope:** M (3-4 files)

### Checkpoint 5: Complete
- [ ] Semua 10 fitur berfungsi
- [ ] `flutter analyze` clean
- [ ] `flutter test` pass
- [ ] Build release APK berhasil
- [ ] Ready for review

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Voice message upload size | Medium | Compress audio sebelum upload (AAC, 64kbps) |
| Typing indicator bandwidth | Low | Broadcast hanya aktif saat chat open, debounce 2 detik |
| Realtime subscription limit | Medium | Gunakan 1 channel per fitur, unsubscribe saat dispose |
| Battery drain dari nearby scan | Medium | Rate limit 30 detik, cache hasil 1 menit |
| Breaking changes di schema | High | Semua migration dalam 1 file SQL, test di dev dulu |
| Multi-language string coverage | Medium | Mulai dari screen utama dulu, tambah bertahap |

## Open Questions
- Voice message storage: Supabase Storage atau dedicated S3?
- Custom notification sound: file audio bawaan atau generate?
- Nearbby scan: tampilkan semua user atau filter by interests?

---

# Phase 6: Audio Sharing & Background Player (MP3 di Chat)

## Overview
Kirim file audio (MP3/umum) sebagai pesan chat dan putar dengan background
playback. Referensi spec: `docs/SPEC-audio-sharing.md`.

## Architecture Decisions
- **Storage**: bucket `audio-files` (public read, upload owner-only, pola `avatars`).
  Path `{auth.uid()}/audio_{timestamp}.mp3`.
- **Message**: kolom baru `is_audio`, `audio_url`, `audio_name`,
  `audio_duration` — terpisah dari `is_voice`. RLS `messages` existing tetap
  berlaku (accepted friend + not blocked).
- **Player**: `just_audio` + `audio_service` (background). Sinkronisasi dengan
  voice player (`audioplayers`): play satu → stop yang lain.
- **Auto-next queue**: urut dari riwayat pesan `is_audio` di percakapan itu.

## Task List

### Task 12: Schema & Bucket Audio (backend)
**Description:** Kolom audio di `messages`, bucket `audio-files` + policy, index.
**Acceptance criteria:**
- [ ] `messages` punya `is_audio`, `audio_url`, `audio_name`, `audio_duration`
- [ ] Bucket `audio-files` public read + upload owner-only (`= auth.uid()`)
- [ ] `backend/schema.sql` (single source of truth) terbarui
**Verification:** SQL valid & idempotent; `flutter analyze` tetap clean
**Dependencies:** None
**Estimated scope:** S

### Task 13: Upload & Kirim Pesan Audio
**Description:** Pilih file audio dari perangkat, validasi, upload ke bucket,
kirim sebagai message `is_audio`.
**Acceptance criteria:**
- [ ] Tombol attach di input chat membuka file picker
- [ ] Validasi: seluruh ekstensi (mp3/m4a/aac/wav), max 25 MB
- [ ] Pesan `is_audio` terkirim dengan url, nama file, durasi
- [ ] Semua string baru pakai i18n
**Verification:** `flutter analyze` clean; kirim file manual berhasil
**Dependencies:** Task 12
**Files:** `services/audio_message_service.dart`, `chat_detail_screen.dart`,
`locale_service.dart`
**Estimated scope:** M

### Task 14: Player & Background Service (just_audio + audio_service)
**Description:** Setup dependency, deklarasi service di AndroidManifest,
MediaService handler global + queue dari riwayat.
**Acceptance criteria:**
- [ ] `just_audio`, `audio_service`, `file_picker` ditambahkan (sudah disetujui)
- [ ] AndroidManifest deklarasi `AudioService` + permission
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK`
- [ ] Loader queue memuat pesan `is_audio` dari percakapan
- [ ] Notifikasi media muncul saat background play
**Verification:** `flutter analyze` clean; build APK berhasil
**Dependencies:** Task 13
**Files:** `pubspec.yaml`, `android/.../AndroidManifest.xml`,
`services/media_controller.dart`, `main.dart`
**Estimated scope:** M

### Task 15: Bubble Audio di Chat + Auto-Next
**Description:** Widget bubble audio (nama file, durasi, play/pause, progress)
terhubung ke global player, plus sinkronisasi voice player & auto-next.
**Acceptance criteria:**
- [ ] Bubble `is_audio` menampilkan nama file, durasi, play/pause, progress
- [ ] Play audio → voice player berhenti (dan sebaliknya)
- [ ] Lagu berakhir → lanjut ke lagu berikutnya di riwayat
**Verification:** `flutter analyze` clean; manual: kirim 2 lagu, putar, test background
**Dependencies:** Task 13, 14
**Files:** `widgets/audio_message_bubble.dart`, `chat_detail_screen.dart`,
`voice_service.dart` (stop)
**Estimated scope:** M

### Checkpoint: Audio Sharing
- [ ] Upload + kirim + tampil di bubble berfungsi
- [ ] Playback berjalan di background dengan kontrol media
- [ ] Auto-next antar lagu berfungsi
- [ ] `flutter analyze` clean
- [ ] Review dengan Bos

## Risks and Mitigations (Phase 6)
| Risk | Impact | Mitigation |
|------|--------|------------|
| Upload 25MB lambat | Med | Validasi size client; satu file per pesan |
| Tabrakan dua player | Med | One-global-player; stop sisi lain saat play |
| Background/silent kill Android OEM | Med | Foreground service media + dokumentasi exclude battery |
| Durasi tidak terbaca | Low | Fallback 0 / tampilkan nama file saja |

## Open Questions (Phase 6)
- Perlu control next/prev di notifikasi atau cukup play/pause + auto-next? (default: ikut auto-next)

---

# Phase 7: Listening Indicator (Sedang Mendengarkan Music MP3)

## Overview
Indikator realtime di chat: saat satu pihak memutar pesan MP3
(`is_audio` via `audio_service`), lawan chat melihat
**"<nama> sedang mendengarkan <judul file>"** — mirror dari `TypingService`.
Referensi spec: `docs/SPEC-listening-status.md`.

## Architecture Decisions
- **Transport**: Supabase Realtime **broadcast** (ephemeral), channel per
  pasangan chat — pola `TypingService` (`zenlook_listening_{sortedIds}`).
- **Emit source**: pantau `gAudioService.playbackState` + `mediaItem` di
  `ChatDetailScreen`. MediaItem.title = nama file. Dedupe: hanya kirim saat
  (listening-on, judul) berubah → aman untuk auto-next & notifikasi kontrol.
- **Hanya `is_audio`**: voice message pakai player terpisah, tidak memicu.
- **Cleanup**: `notifyStopped()` di `dispose`; peer punya timeout fallback ~8s.

## Task List
- **Task 16**: `ListeningService` (broadcast, dedupe, dispose).
- **Task 17**: Wiring play/stop ke broadcast di `ChatDetailScreen`.
- **Task 18**: UI indikator peer + key i18n `chat_listening_music`.

## Dependency Graph
```
ListeningService
    └── ChatDetailScreen (emit: playbackState/mediaItem)
            └── UI indikator peer (locale_service key)
```

## Checkpoint: Listening Indicator
- [ ] Indikator muncul realtime, hilang saat pause/stop/tutup
- [ ] Ikon music + nama file; fallback "music mp3" bila nama kosong
- [ ] `flutter analyze` clean

## Risks and Mitigations (Phase 7)
| Risk | Mitigation |
|------|------------|
| Event stop terlewat (kill app) | Timeout fallback 8s + reset di dispose |
| Auto-next spam broadcast | Dedupe (on, judul) sebelum kirim |
| Aplikasi jadul/dua tab | Broadcast hanya aktif saat chat terbuka |
