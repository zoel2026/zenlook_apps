-- ============================================================================
-- Trigger push notification pesan baru (2026-08-23)
--
-- Setiap INSERT ke `messages` akan memanggil Edge Function `send-push`
-- lewat pg_net (async, tidak memperlambat insert).
--
-- PRASYARAT (dikerjakan sekali):
--   1. Edge Function send-push SUDAH di-deploy ke project Supabase.
--   2. Secret FIREBASE_SERVICE_ACCOUNT sudah di-set di Supabase.
--
-- Jalankan: Supabase Dashboard > SQL Editor > New query > paste > Run.
-- Idempotent — aman dijalankan berulang.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Aktifkan pg_net (untuk HTTP request dari dalam database)
-- ---------------------------------------------------------------------------
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- 2. Trigger function: kirim push saat ada pesan baru
--    NOTE: anon key ditulis langsung — itu BUKAN rahasia (publik by design).
--    Kalau project Supabase diganti, update v_url dan v_key!
-- ---------------------------------------------------------------------------
create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_url         text := 'https://ytmkhmsndfwmjlfyxiiw.supabase.co/functions/v1/send-push';
    v_key         text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0bWtobXNuZGZ3bWpsZnl4aWl3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwOTk5NzksImV4cCI6MjEwMjY3NTk3OX0.klvdt6g4MhTKusBhuGKxPrjUQHt8DsOsTVXFH1dF9zo';
    v_sender_name text;
begin
    -- Nama pengirim sebagai judul notifikasi.
    select coalesce(nullif(full_name, ''), username, 'Zenlook')
      into v_sender_name
      from profiles
      where id = new.sender_id;

    perform net.http_post(
        url := v_url,
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_key
        ),
        body := jsonb_build_object(
            'userId',   new.receiver_id,
            'title',    coalesce(v_sender_name, 'Zenlook'),
            'body',     new.content,
            'senderId', new.sender_id
        )
    );

    return new;
end;
$$;

drop trigger if exists messages_notify_push on public.messages;
create trigger messages_notify_push
    after insert on public.messages
    for each row execute procedure public.notify_new_message();
