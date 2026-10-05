# Spec: Status & Aktivitas — " lagi di mana?" 📍

## Objective
Pengguna bisa menulis status singkat (mis. "lagi ngerjain skripsi", "di kantin
☕") yang terlihat teman-temannya di daftar teman dan panel monitoring peta.
Status punya masa berlaku otomatis supaya tidak ada yang basi.

## Keputusan
- **Disimpan di `profiles`, bukan tabel baru**: status adalah atribut profil,
  dibaca bersamaan dengan data profil yang sudah ada.
- **Expire di sisi client**, tanpa cron: `status_expires_at` sudah lewat →
  status dianggap kosong. Tidak perlu job pembersihan.
- **Tanpa Realtime di versi pertama**: status tampil saat layar dibuka/di-refresh.
  Subscribe `profiles` ditambahkan sebagai pekerjaan lanjutan (lihat Future).
- Dibaca semua user ter-autentikasi lewat policy `profiles_select_others` yang
  sudah ada; ditulis hanya pemilik lewat `profiles_update_own`.
- Panjang dibatasi di database (60 karakter) supaya tidak bisa menyalahgunakan
  kolom ini sebagai kolom bebas.

## Database (`backend/schema.sql`)
```sql
alter table public.profiles add column if not exists status_text text;
alter table public.profiles add column if not exists status_emoji text;
alter table public.profiles add column if not exists status_expires_at timestamptz;
```
- Constraint (dibungkus `do $$ ... $$` supaya aman dijalankan ulang):
  `status_text is null or char_length(status_text) <= 60`.
- Tidak ada tabel/policy/index baru → tidak adaRLS baru yang bisa keliru.

## Flutter
- `services/status_service.dart`
  - `StatusTtl` (1 jam / 4 jam / 8 jam, default 4 jam).
  - `isStatusActive({required String? text, required DateTime? expiresAt,
    required DateTime now})` — **pure**, inti aturan expire.
  - `activeStatusText({required String? text, required DateTime? expiresAt,
    required DateTime now})` — **pure**, teks siap tampil (`null` kalau expired).
  - `setStatus({required String? emoji, required String? text,
    required StatusTtl ttl})` → update `profiles`.
  - `clearStatus()` → kosongkan teks/emoji/expire.
- `screens/profile_tab.dart` — kartu "Status": input teks, pilihan emoji,
  pilihan masa berlaku, tombol Simpan & Hapus, pratinjau masa berlaku.
- `widgets/map_monitoring_panel.dart` — status teman tampil di bawah nama.
- `screens/friends_tab.dart` — status teman tampil di baris daftar teman.
- i18n: `status`, `status_placeholder`, `status_save`, `status_clear`,
  `status_expires_in`, `status_saved`, `status_cleared`, `status_empty_hint`,
  `status_ttl_1h`, `status_ttl_4h`, `status_ttl_8h` (ID/EN).

## Verification
- `flutter analyze` clean; `flutter test` hijau (termasuk
  `test/status_service_test.dart` untuk aturan expire).
- SQL: terapkan `backend/schema.sql` di Supabase SQL Editor, lalu uji manual:
  set status → terlihat di daftar teman → hangus otomatis setelah TTL.

## Boundaries
- Always: hanya pemilik yang bisa mengubah statusnya sendiri; maksimum 60
  karakter; expired diperlakukan sebagai tidak ada.
- Never: status tidak pernah mengandung lokasi presisi (itu urusan peta);
  tidak ada push notification untuk perubahan status.

## Future
- Realtime `profiles` agar status teman berubah tanpa perlu refresh.
- "Lagi dipakai aplikasi X" (mirip Zenly) kalau data pemakaian dibutuhkan.
- reacting ke status (like/emoji) kalau ada umpan balik dari teman.