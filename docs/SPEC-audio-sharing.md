# Spec: Audio Sharing & Background Player (MP3 di Chat)

## Overview

User Zenlook dapat **mengirim file audio (utamanya MP3)** lewat chat, dan
penerima memutarnya langsung di bubble chat — termasuk **background playback**
(layar mati / app di background) dengan kontrol notifikasi media bergaya
Android, plus queue agar lagu lanjut otomatis.

Ini adalah fitur baru, terpisah dari *voice message* yang sudah ada
(`is_voice`, recorder, max 60 detik). Audio sharing menyasar **file/song**,
bukan rekaman singkat.

## Capability Map

| Module id | Responsibility | Depends on |
|---|---|---|
| `audio-messages` | Bucket storage baru, kolom di `messages`, upload + kirim pesan audio dari chat | — |
| `audio-player` | Bubble audio di chat: play/pause, progress, nama & durasi, sinkronasi dengan voice player | `audio-messages` |
| `audio-background` | Playback di background via `just_audio` + `audio_service` (notifikasi media, next/prev, queue riwayat) | `audio-player` |

Build order: `audio-messages` → `audio-player` → `audio-background`

## Objective

- [ ] Pengguna bisa memilih file audio dari perangkat dan mengirimnya sebagai pesan chat
- [ ] Pesan audio tampil sebagai bubble (nama file, durasi, tombol play/pause, progress)
- [ ] Audio bisa diputar saat app di foreground maupun background (layar mati)
- [ ] Kontrol media muncul di notifikasi (play/pause/next/prev) saat background
- [ ] Audio yang sedang diputar berhenti otomatis di akhir lagu, lanjut ke lagu berikutnya dari riwayat percakapan
- [ ] Berbeda dengan voice message: tidak dibatasi 60 detik, menampilkan nama file
- [ ] Yg diblokir tidak bisa mengirim/mendengar audio (ikuti RLS `messages` yang sudah ada)

## Tech Stack

- Flutter (existing) + Supabase Storage/PostgreSQL
- Dependency baru (perlu persetujuan): `file_picker`, `just_audio`, `audio_service`

## Commands

```
Analyze:  flutter analyze
Test:     flutter test
Build APK: flutter build apk --release
```

## Project Structure

```
app/lib/
  services/audio_service.dart        → upload & kirim pesan audio
  services/media_controller.dart     → global player (just_audio/audio_service)
  widgets/audio_message_bubble.dart  → bubble play/pause di chat
  screens/chat_detail_screen.dart    → tombol attach + integrasi bubble
backend/schema.sql                   → kolom baru + bucket + policy (single source of truth)
```

## Data Model (backend)

```sql
alter table public.messages
  add column if not exists is_audio      boolean not null default false,
  add column if not exists audio_url     text,
  add column if not exists audio_name    text,
  add column if not exists audio_duration double precision;
```

- Bucket storage baru `audio-files`: public read, upload owner-only
  (pola sama seperti bucket `avatars`).
- RLS `messages` tidak perlu diubah: `is_audio` opsional, kebijakan
  insert/select yang ada (`accepted friend`, `not blocked`) tetap berlaku.

## Code Style

Ikuti pola yang ada di service layer (`maybeClient()` guard, static method),
i18n via `context.l.t(...)`, tema via `AppColors`/`context.textPrimary`.

## Testing Strategy

- `flutter analyze` bersih
- Widget test untuk bubble audio (render nama file + tombol) bila feasible
- Tidak dilakukan test end-to-end ke Supabase Storage di unit test (butuh env)
- Verifikasi manual: kirim MP3 → muncul bubble → putar → pindah background → tetap lanjut

## Boundaries

- Always: pakai i18n untuk semua string baru; `maybeClient()` guard; ikuti RLS existing
- Ask first: menambah dependency (`file_picker`, `just_audio`, `audio_service`),
  perubahan `AndroidManifest.xml`, ukuran/format file limit
- Never: menaruh secret; merusak RLS `messages`; mengubah perilaku voice message yang sudah ada

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Ukuran upload besar (25MB) | Medium | Validasi ekstensi+size sebelum upload; file_picker tanpa memindahkan file besar |
| Dua player berdampingan (voice `audioplayers` + audio `just_audio`) | Medium | Sinkronisasi: play satu → stop yang lain |
| Background audio butuh manifest service | Low | Deklarasi `AudioService` + permission `FOREGROUND_SERVICE_MEDIA_PLAYBACK` di AndroidManifest |
| Durasi file tidak terbaca | Low | Fallback durasi = 0 / langsung play |

## Open Questions

- Batas ukuran file: default 25 MB — cukup?
- Format: MP3 saja atau + M4A/WAV (asumsi: semua audio umum didukung)?
- Auto-next queue disetujui sebagai perilaku MVP?

## Lokasi

Dokumen ini menyatu dengan plan/task di `tasks/plan.md` dan `tasks/todo.md`.