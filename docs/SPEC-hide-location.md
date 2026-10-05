# Spec: Sembunyikan Lokasi dari Teman Tertentu

## Objective
Seorang pengguna bisa memilih teman tertentu yang **tidak** boleh melihat
lokasinya, tanpa harus memblokir atau berhenti jadi teman. Teman yang
disembunyikan masih dapat membuka chat dan melihat status aktivitas, tetapi
titik lokasi tidak dikirim dan tidak tampil di peta.

## Keputusan
- **Tabel relasi baru `location_visibility`**, bukan kolom di `locations`.
  Visibilitas adalah hubungan antar-pengguna (saya ↔ dia), sedangkan `locations`
  menyimpan satu baris per pengguna. Satu baris per pasangan pengguna membuat
  matriks visibilitas bisa bertumbuh tanpa menulis ulang tabel `locations`.
- **Ditegakkan di RLS, bukan di client**: policy `locations_select_friends`
  ditambah syarat "tidak ada entri sembunyi untuk pasangan ini". Kalau hanya
  disembunyikan di app, siapa pun yang punya anon key masih bisa SELECT langsung
  lewat REST — dan `location_history` juga ada.
- **Sembunyi bersifat dua arah?** Tidak. Hanya pemilik lokasi yang memilih siapa
  yang tidak boleh melihat. Kalau A menyembunyikan dari B, B tetap melihat A
  sampai B memilih menyembunyikan A juga.
- **Teman yang disembunyikan tetap di daftar teman**; hanya lokasi yang hilang.
  Menyingkirkan teman sepenuhnya adalah fitur blokir yang sudah ada.

## Database (`backend/schema.sql`)
```sql
create table if not exists public.location_visibility (
  user_id uuid not null references public.profiles(id) on delete cascade,
  hidden_from_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, hidden_from_id),
  check (user_id <> hidden_from_id)
);
```
- RLS aktif. Policy select/delete hanya untuk `user_id = auth.uid()` (daftar
  penyembunyi milik pengguna itu sendiri). Tidak ada policy insert: entri baru
  hanya dibuat lewat RPC.
- RPC `set_location_hidden(p_peer uuid, p_hidden boolean)` `security definer`,
  `set search_path = public`, dengan validasi: harus teman accepted, tidak
  menyembunyikan diri sendiri, dan tidak ada blokir dua arah. Upsert/delete.
- `locations_select_friends` ditambah:
  `and not exists (select 1 from public.location_visibility lv where lv.user_id = locations.user_id and lv.hidden_from_id = auth.uid())`
- `get_nearby_users` (RPC yang dipakai scan nearby) disaring dengan syarat
  yang sama supaya orang yang disembunyikan tidak muncul dari scan radar.

## Flutter
- `services/location_visibility_service.dart`
  - `hidePeerFrom()` / `showPeerTo()` memanggil RPC (pure mapping error).
  - `hiddenPeerIds()` membaca daftar id yang sedang disembunyikan.
- `screens/friends_tab.dart`: tombol mata pada tiap baris teman untuk
  menyalakan/mematikan sembunyi lokasi.
- `screens/profile_tab.dart`: kartu "Lokasi disembunyikan dari (n)" + Manage
  untuk mengatur daftar.
- `FriendData.activityLine` sudah ada; tambahan `locationHidden: bool` supaya
  panel monitoring peta bisa menampilkan "Lokasi disembunyikan" alih-alih
  koordinat kosong yang membingungkan.
- i18n: `hide_location`, `hide_location_from`, `show_location_to`, `location_hidden_badge`, `manage_hidden_locations`, `hidden_locations_empty`, `hide_location_confirm`.

## Verification
- `flutter analyze` clean; `flutter test` hijau.
- SQL manual: sembunyikan B dari A → query `locations` sebagai B mengembalikan
  nol baris untuk A; `get_nearby_users` tidak memuat A; A tetap bisa SELECT
  lokasinya sendiri.

## Boundaries
- Always: hanya pemilik lokasi yang mengatur; tidak ada efek ke chat, status,
  atau daftar teman; sesame tetap bisa memblokir seperti biasa.
- Never: tidak pernah menyembunyikan lokasi dari blokir secara otomatis;
  tidak ada lokasi coarse/fuzzy sebagai pengganti (pakai blokir untuk itu).

## Future
- Sematkan dengan setting "Bagikan lokasi hanya ke ..." (whitelist) memakai
  tabel yang sama dengan polaritas terbalik.
- Notifikasi ke teman bahwa lokasi disembunyikan (sementara tidak ada —
  berisiko mengganggu).