# Spec: Hapus Pesan (Delete for Me / for Everyone)

## Objective
Pengguna bisa menghapus pesan yang sudah terkirim. Dua mode:

- **Hapus untuk saya saja**: pesan hilang di perangkat saya, tetap ada di
  perangkat lawan.
- **Hapus untuk semua orang**: teks pesan dikosongkan (soft delete) supaya
  tidak ada pemulihan isi pesan lewat data lama.

Belum ada mode "edit pesan" atau "hapus untuk semua dengan batas waktu".

## Keputusan
- **Soft delete dengan kolom baru, bukan `delete` baris**: menghapus baris
  `messages` akan ikut menghapus baris `message_reactions` dan merusak urutan
  `load more` (cursor pagination) karena `created_at` akan bolong di tengah.
  Soft delete menjaga urutan dan histori.
- **Isi pesan dikosongkan, bukan dihapus dari DB**: row tetap ada supaya
  "pesan ini dihapus" bisa ditampilkan dan reaksi lama tidak menggantung.
  Kolom `content` NOT NULL, jadi kosong direpresentasikan sebagai `''`. Server
  yang mengosongkan (bukan client), lewat trigger: dengan begitu isi lama tidak
  bisa dipulihkan meski ada yang SELECT langsung.
- **Hanya pengirim boleh menghapus**: itu syarat minimal untuk "hapus untuk
  semua". Enhancement (moderasi) di luar scope.
- **"Hapus untuk saya saja" memakai soft delete yang sama**, dengan
  `deleted_by` dibiarkan `null` sehingga tidak ada jejaknameof penghapus di
  sisi lawan. Trade-off yang diketahui dan disepakati: mode ini juga
  mengosongkan isi di sisi server, jadi pesan ikut hilang untuk semua pihak.
  Menghilangkan isi hanya di perangkat sendiri butuh daftar id lokal
  (`hidden_messages`) dan itu pekerjaan lanjutan, bukan versi pertama.

## Database (`backend/schema.sql`)
```sql
alter table public.messages add column if not exists is_deleted boolean not null default false;
alter table public.messages add column if not exists deleted_at timestamptz;
alter table public.messages add column if not exists deleted_by uuid;
```
- Policy baru `messages_delete_own` (for update, `auth.uid() = sender_id`).
  RLS hanya membatasi baris; pemisahan kolom per role tetap di trigger.
- `messages_update_guard` diperluas jadi allowlist per role: pengirim hanya
  boleh mengubah `is_deleted`/`deleted_at`/`deleted_by`, dan `content` hanya
  boleh menjadi `''` tepat saat pesan ditandai terhapus; penerima tetap hanya
  boleh `read_at`. Perubahan `is_deleted` dari true kembali ke false ditolak
  supaya pesan tidak bisa "dihidupkan" lagi.
- Tanpa index baru: query chat sudah memakai `messages_pair_idx` yang ada.
- Realtime: `messages` sudah ada di publikasi realtime. Karena payload update
  ikut menimpa `is_deleted`, penerima melihat perubahan tanpa fetch ulang.

## Flutter
- `services/message_service.dart`
  - `DeleteScope` (onlyMe / everyone) + `deleteMessageKey(DeleteScope)` (pure,
    kunci i18n) + `mapDeleteErrorToResult({code, message})` (pure).
  - `visibleMessageContent(MessageContentArgs)` (pure) → isi yang boleh
    ditampilkan, `null` bila pesan kosong atau sudah dihapus.
  - `deleteMessage({required String messageId, required DeleteScope scope})`
    → `is_deleted: true`, `deleted_at: now()`, `deleted_by: scope == onlyMe
    ? null : uid`. Update dibatasi `.eq('sender_id', uid)` + `.select('id')`,
    jadi nol baris terbalik sebagai `DeleteResult.notAllowed`.
- `visibleMessageContent` menentukan bubble: teks, tombol suara, dan file audio
  diganti teks "Pesan ini dihapus" (i18n `message_deleted`).
- `widgets/message_delete_button.dart`: tombol hapus + sheet pilihan cakupan +
  dialog konfirmasi. Diekstrak supaya `chat_detail_screen.dart` yang sudah
  1.081 baris tidak bertambah jauh; file itu hanya menambahkan pemanggilan
  tombol dan kolom `is_deleted` ke dalam query select.

## Verification
- `flutter analyze` clean; `flutter test` hijau:
  - `test/message_service_test.dart` (9 test) — mapper kunci i18n, pemeta error
    Postgrest, dan `visibleMessageContent` untuk pesan terhapus.
  - `test/message_delete_button_test.dart` (3 test) — sheet cakupan hapus,
    dialog konfirmasi, dan pembatalan tidak memanggil service.
- SQL: terapkan `backend/schema.sql`, lalu uji manual:
  1. Hapus untuk semua → lawan melihat "Pesan ini dihapus" tanpa refresh.
  2. Hapus untuk saya → pesan hilang di daftar.
  3. Coba `update messages set is_deleted = false` manual pada pesan yang
     sudah dihapus → harus ditolak trigger.

## Boundaries
- Always: hanya pengirim; tidak ada pembatalan; isi pesan yang sudah dihapus
  tidak dapat dipulihkan lewat trigger maupun UI.
- Never: baris `messages` tidak pernah dihapus fisik; reaksi lawan tidak
  dihapus di server (hanya dibersihkan dari daftar lokal setelah dihapus).

## Future
- Rombak `chat_detail_screen.dart` (1.081 baris) jadi beberapa widget.
- Batas waktu "hapus untuk semua" (mis. 15 menit).
- `hidden_messages` agar "hapus untuk saya" benar-benar hanya lokal.
- Bersihkan reaksi di server saat pesan dihapus untuk semua orang.