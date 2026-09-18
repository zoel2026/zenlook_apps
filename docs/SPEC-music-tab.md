# Spec: Music Tab — Musik MP3 Lokal / Radio dari Storage

## Objective
Tab baru **Musik** di HomeScreen. User memilih file MP3 dari penyimpanan
handphone (file_picker), lalu diputar lewat player global `audio_service`
(background + notifikasi media + kontrol lock screen). Playback musik
memicu **listening status** (temannya lihat judul lagu) — otomatis lewat
jalur `gAudioService.playbackState` yang sudah dipantau ChatDetailScreen.

## Tech Stack (SEMUA dependency sudah ada — tanpa dep baru)
- `just_audio: ^0.9.46` + `audio_service: ^0.18.19` (player global `AudioPlayerService`)
- `file_picker: ^12.2.0` (ambil MP3 dari storage HP)

## Commands
- Analyze: `flutter analyze`
- Test: `flutter test`
- Build: `flutter build apk --release`

## Project Structure
```
lib/services/music_library.dart   # PURE: model MusicTrack + tracksFromPaths() + formatDuration() (unit-testable)
lib/screens/music_tab.dart        # UI: list antrean, play/pause/next/prev, tambah MP3, hapus
lib/screens/home_screen.dart      # tambah 5th tab (NavigationBar)
lib/services/locale_service.dart  # key baru id/en (music, add_music, no_music, now_playing, clear_queue)
test/music_library_test.dart      # unit test pure logic
docs/SPEC-music-tab.md            # spec ini
```

## Code Style
Ikuti pola existing: service static/pure, state lokal StatefulWidget dengan
satu pemutar (`gAudioService`), teks via `context.l.t('key')`. Model immutable.

## Testing Strategy
- Unit (`test/music_library_test.dart`): URI/title dari path file, format durasi, queue build.
- Widget minimal: empty state MusicTab (tanpa platform channel).

## Boundaries
- Always: `flutter analyze` + `flutter test` hijau sebelum selesai.
- Always: play via `gAudioService` (jangan create AudioPlayer baru sendiri).
- Ask first: tidak ada (semua dep sudah terpasang; tak menyentuh DB/schema).
- Never: tulis file di luar app sandbox, hardcode path MP3, menyimpan lokasi file permanen tanpa izin.

## Success Criteria
1. Tab "Musik" tampil di nav bawah HomeScreen.
2. Pilih ≥1 MP3 → muncul di list; tap → play player global (background + notifikasi media).
3. Judul (nama file) tampil, ada play/pause, next/prev, stop, hapus item.
4. Ambil jalan: `FilePicker` MP3 → queue `MediaItem` (uri file://) → `loadQueue` → `playQueueIndex`.
5. Musik yang diputar memicu listening status ke teman (jalur `playbackState` existing).
6. `flutter analyze` clean; unit test baru pass.

## Open Questions
- Queue bersifat **per-sesi** saja (tidak dipersist) — OK?
- Bahasa nav: "Musik" (id) / "Music" (en) — OK?