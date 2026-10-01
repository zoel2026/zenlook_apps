# Spec: Wave — Ping "Di mana kamu?" 👋

## Objective
Kirim gelombang (wave) ke teman sebagai isyarat ringan "di mana kamu? /
ayo ketemuan". Penerima dapat push notification saat app tertutup, dan
banner in-app saat app terbuka. Bukan chat — tidak memuat pesan teks.

## Keputusan
- **Bukan ephemeral murni**: wave disimpan di tabel `waves` agar bisa
  realtime, dedupe, dan audit singkat.
- **Cooldown 5 menit** per pasangan pengirim→penerima, di-enforce
  server-side (trigger), bukan hanya di client.
- **Hanya teman accepted** & tidak saling blokir (dijaga RLS).
- Push lewat infrastruktur yang sudah ada: trigger → `pg_net` →
  Edge Function `send-push` (type `wave`).

## Database (`backend/schema.sql`)
```sql
create table public.waves (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (sender_id <> receiver_id)
);
```
- Trigger `waves_cooldown_guard` (BEFORE INSERT) → tolak jika ada wave
  pasangan sama < 5 menit (errcode `unique_violation`).
- Trigger `waves_notify_push` (AFTER INSERT) → `net.http_post` ke
  `send-push` dengan body `{ type:'wave', userId, title, body, senderId }`.
- RLS: insert own (teman accepted, tak blokir), select/delete involved.
- Realtime: `waves` ditambahkan ke publikasi `supabase_realtime`.

## Edge Function `send-push`
Tidak ada penanganan khusus: field `type` & `senderId` sudah diteruskan
apa adanya ke data payload. App membedakan via `data['type']`.

## Flutter
- `services/wave_service.dart`
  - `WaveResult` (sent/cooldown/blocked/failed) + `waveResultFromError()` (pure).
  - `sendWave({fromId, toId})` → insert `waves`.
  - `watchIncoming({myId, onWave})` → realtime channel filter `receiver_id`.
- `screens/chat_detail_screen.dart` — tombol Wave (👋) di app bar;
  snackbar hasil (terkirim / cooldown / tidak bisa / gagal).
- `screens/home_screen.dart` — listener global wave masuk → `MessageBanner`
  (di-skip bila chat dengan pengirim sedang terbuka).
- Push FCM foreground/background sudah menampilkan notifikasi dari payload
  generik (title/body) — tidak perlu perubahan.
- i18n: `wave`, `wave_send_tooltip`, `wave_sent`, `wave_cooldown`,
  `wave_blocked`, `wave_failed`, `wave_received_banner` (ID/EN).

## Verification
- `flutter analyze` clean; `flutter test` hijau (termasuk
  `test/wave_service_test.dart`).
- SQL: terapkan `backend/schema.sql`; uji manual 2 akun (cooldown, blokir,
  push saat app tertutup).

## Boundaries
- Always: cooldown 30 mnt? → **5 menit**; hanya teman accepted; exclude blokir.
- Never: memuat pesan teks; mengirim notifikasi ke user yang memblokirku.

## Open Questions
- Entry point tambahan (friends list / map monitoring panel) — MVP saat ini
  hanya dari layar chat.
