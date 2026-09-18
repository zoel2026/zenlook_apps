# Spec: Listening Indicator (Sedang Mendengarkan Music MP3)

## Objective

Ketika pengguna **memutar pesan audio (MP3)** di chat, lawan bicara melihat
indikator **"Budi sedang mendengarkan <nama file>.mp3"** di layar chat —
mirip indikator typing (`sedang mengetik...`). Indikator tampil **selama lagu
diputar**, dan hilang saat user **pause / stop / menutup chat**, atau
ada jeda tanpa pembaruan (fallback timeout).

Fitur ini hanya untuk **audio message** (`is_audio`, lewat `audio_service`),
bukan voice message (`is_voice`, lewat `audioplayers`).

## Acceptance Criteria

- [ ] Indikator "sedang mendengarkan <judul>" muncul di chat lawan secara
      realtime (broadcast, bukan postgres changes) saat saya memutar MP3.
- [ ] Nama file MP3 ikut tampil (mis. `sedang mendengarkan lagu.mp3`).
- [ ] Indikator hilang saat pause / stop / auto-next berhenti — dan pastinya
      saat layar chat ditutup.
- [ ] Fallback timeout: indikator otomatis hilang ~8 dtk tanpa pembaruan
      (jaga-jaga event "stop" terlewat).
- [ ] Tidak muncul untuk pesan voice (voice bubble tidak memicu broadcast).
- [ ] `flutter analyze` bersih; tidak ada test baru yang gagal.

## Tech Stack

- Flutter existing + Supabase Realtime (broadcast) — pola sama dengan
  `TypingService`. Tidak ada dependency baru.

## Commands

```
Analyze: flutter analyze
Test:    flutter test
```

## Project Structure

```
app/lib/services/listening_service.dart  → ListeningService (broadcast realtime)
app/lib/screens/chat_detail_screen.dart  → init/subscribe, emit state, indicator UI
app/lib/services/locale_service.dart     → key i18n ID/EN (chat_listening_music)
```

## Code Style

Ikuti `TypingService` persis:
- single channel broadcast per pasangan chat, channel name di-sort,
- guard `maybeClient()`, semua string lewat `context.l.t(...)`.

## Data Model

Tidak ada perubahan DB. Murni Realtime broadcast ephemeral seperti typing.

## Testing Strategy

- Unit/widget test untuk logika state indikator bila feasible (tanpa
  Supabase terinit). Jika tidak feasible, verifikasi manual via dua device.
- `flutter analyze` clean.

## Boundaries

- Always: pakai i18n; broadcast hanya saat chat dibuka; cleanup di `dispose`.
- Ask first: menambah dependency baru, perubahan schema DB.
- Never: menambah beban ke postgres changes untuk event ephemeral ini (pakai
  broadcast), mengubah perilaku typing/voice yang sudah ada.

## Risks

| Risk | Mitigation |
|------|------------|
| Event "stop" terlewat (kill app) | Timeout fallback ~8 dtk + reset saat dispose |
| Nama file kosong | Fallback ke teks `music mp3` |
| Spam broadcast saat auto-next | Dedupe: hanya kirim bila (on, nama) berubah |