# Spec: Nearby Alert — Notifikasi User Terdekat

## Objective
User bisa mengaktifkan alert: dapat notifikasi push saat ada pengguna lain
(yang bukan self dan bukan blokir) masuk radius (default **500 m**) dari posisi
terkini. Deteksi **di sisi server** saat lokasi di-upsert (jalan walau app
penerima tertutup, karena saya mengaktifkan alert di lokasi saya).

Satu arah: penerima alert yang enable; pengirim TIDAK perlu enable.

## Keputusan (disetujui Bos)
- Radius default 500 m (user bisa atur 100–1000 m via Profile)
- Satu arah: saya enable → bisa kena notif saat ada pengguna dekat saya
- Cooldown: **1 notif / user pemicu / 30 menit** (anti spam)

## Tech Stack (tanpa dependency baru)
- Supabase trigger `BEFORE/AFTER insert or update on locations`
- `pg_net` → Edge Function `send-push` (di-extend dukung tipe `nearby`)
- FCM foreground → local notification via `PushService` (Flutter)

## Database (backend/schema.sql)
```sql
alter table public.profiles
  add column if not exists nearby_alerts_enabled boolean not null default false,
  add column if not exists nearby_alert_radius integer not null default 500;

create table if not exists public.nearby_alert_cooldown (
  alerter_id uuid not null references auth.users(id) on delete cascade,
  target_id  uuid not null references auth.users(id) on delete cascade,
  last_at    timestamptz not null default now(),
  primary key (alerter_id, target_id)
);
-- policy: NONE (table internal, service-role/security-definer only)
-- + index untuk lat/lng prefilter: create index locations_latlng_idx
--   on public.locations (latitude, longitude);
```

- Kolom `profiles.nearby_alerts_*` kita baca trigger as `postgres` (security
  definer) → terbaca meski RLS.

## Fungsi trigger `notify_nearby_users`
`AFTER INSERT OR UPDATE ON locations`, security definer, search_path public.
Langkah:
1. Skor `latitude`/`longitude` valid, bukan self.
2. Ambil calon alerter (profiles `nearby_alerts_enabled = true`, excl. self,
   radius user masing-masing, dalam box lat/lng sekitar titik baru).
3. Filter `not is_blocked(alerter, target)` dua arah.
4. Cooldown: cek `nearby_alert_cooldown(alerter, target)` < 30 menit → skip;
   kalau lolos, upsert `last_at = now()`.
5. Ambil nama target dari profiles.
6. `net.http_post` → `https://<ref>.supabase.co/functions/v1/send-push`
   dengan header `x-internal-key` dari `app_secrets` + body:
   `{ type: 'nearby', userId: <alerter>, name: <nama target>,
      distanceM: <round>, latitude, longitude }`.
- Body push: "Orang terdekat: `<name>` (±<distance> m)".

## Edge Function send-push (extend)
- Baca body; bila `type == 'nearby'` → kirim FCM data+notification
  `{ title: 'User terdekat', body: '<name> sekitar <distance> m' }`
  ke token FCM alerter; tanpa isi pesan chat. Tetap wajib `x-internal-key`.

## Flutter
- `services/nearby_alert.dart` (pure): model `NearbyAlertSettings`, validasi
  radius (100–1000), format jarak ("±500 m"), parse payload FCM → teks.
- ProfileTab: toggle "Notifikasi user terdekat" + slider radius.
- FCM foreground handler di `fcm_service.dart`: payload `type=='nearby'` →
  tampilkan via `PushService.show(title, body)` + navigasi opsional ke map.
- Home/Map: tak ada perubahan peta (marker tetap cuma teman).

## Commands & Verifikasi
- `flutter analyze`, `flutter test` (unit NearbyAlertSettings + format + parse)
- SQL: jalankan snippet di staging, uji manual (2 akun, radius 500 m)
- `flutter build apk --release --split-per-abi` setelah selesai

## Boundaries
- Always: enable = opt-in; cooldown 30 mnt; exclude blocked; tak mengirim
  lokasi ke penerima (hanya nama + jarak bulat).
- Always: security definer + search_path + internal key; body tidak boleh
  membocorkan isi chat.
- Ask first: perubahan radius default / hapus cooldown.
- Never: kirim lokasi presisi penerima; notif ke user yang memblokirku.

## Success Criteria
1. Enable alert + user lain masuk radius → terima push ≤ beberapa detik.
2. Radius disesuaikan di Profile (100–1000 m) dan dipakai trigger.
3. Blokir → tidak ada notif dari/ke arah itu.
4. Maksimal 1 notif/user/30 menit.
5. `flutter analyze` clean; unit test baru pass.

## Open Questions
- (none — keputusan di atas sudah mengunci)