-- ============================================================================
-- Privacy hardening (2026-08-23, ronde 2)
--
-- Fix 2 celah dari audit keamanan ronde 2:
--   1. Policy "profiles_select_others" membocorkan email, phone, dan
--      device_token SEMUA user ke setiap user ter-autentikasi
--      (RLS tidak bisa membatasi per kolom).
--      -> Kolom sensitif dipindah ke tabel `private_profiles`
--         dengan RLS own-only.
--   2. Edge Function send-push bisa dipanggil siapa pun yang punya anon key.
--      -> Trigger kini mengirim header x-internal-key; nilainya disimpan di
--         tabel `app_secrets` (tanpa policy = tak terbaca klien).
--         Edge Function membandingkan dgn secret PUSH_INTERNAL_KEY.
--
-- URUTAN AMAN:
--   Install APK baru dulu (atau langsung setelahnya), lalu jalankan patch ini,
--   lalu redeploy edge function + set secret PUSH_INTERNAL_KEY.
--   APK lama sesaat kehilangan fitur edit HP/email & sync token — bukan crash.
--
-- Semua statement idempotent — aman dijalankan berulang kali.
-- Jalankan: Supabase Dashboard > SQL Editor > New query > paste > Run.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tabel private_profiles: data sensitif per user, cuma pemilik yg boleh.
-- ---------------------------------------------------------------------------
create table if not exists public.private_profiles (
    id           uuid primary key references public.profiles (id) on delete cascade,
    email        text,
    phone        text,
    device_token text,
    updated_at   timestamptz not null default now()
);

alter table public.private_profiles enable row level security;

drop policy if exists "private_profiles_select_own" on public.private_profiles;
create policy "private_profiles_select_own"
    on public.private_profiles for select
    using (auth.uid() = id);

drop policy if exists "private_profiles_insert_own" on public.private_profiles;
create policy "private_profiles_insert_own"
    on public.private_profiles for insert
    with check (auth.uid() = id);

drop policy if exists "private_profiles_update_own" on public.private_profiles;
create policy "private_profiles_update_own"
    on public.private_profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- 2. Migrasi data lama: salin email/phone/device_token dari profiles.
--    Idempoten: kalau kolomnya sudah tidak ada (patch pernah jalan),
--    backfill email dari auth.users untuk row yang belum terdaftar.
-- ---------------------------------------------------------------------------
do $$
begin
    if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name  = 'profiles'
          and column_name = 'email'
    ) then
        insert into public.private_profiles (id, email, phone, device_token)
        select p.id, p.email, p.phone, p.device_token
        from public.profiles p
        on conflict (id) do nothing;
    else
        insert into public.private_profiles (id, email)
        select u.id, u.email
        from auth.users u
        on conflict (id) do nothing;
    end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Buang kolom sensitif dari profiles (sumber bocor).
-- ---------------------------------------------------------------------------
alter table public.profiles drop column if exists device_token;
alter table public.profiles drop column if exists phone;
alter table public.profiles drop column if exists email;

-- ---------------------------------------------------------------------------
-- 4. Tabel app_secrets: shared secret trigger <-> edge function.
--    RLS aktif TANPA satu pun policy -> hanya service_role / postgres /
--    security definer yang bisa membaca.
-- ---------------------------------------------------------------------------
create table if not exists public.app_secrets (
    name        text primary key,
    value       text not null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

alter table public.app_secrets enable row level security;

insert into public.app_secrets (name, value)
values (
    'push_internal_key',
    '6dd0c9725234bb90c23907974faf55c3f951419d6e2611341f9cc3dfb8dbcc49'
)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------------
-- 5. handle_new_user: email/phone kini ditulis ke private_profiles.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    base_username text;
    candidate     text;
begin
    -- Sanitize: only [a-z0-9_], max 24 chars. Invalid/empty -> auto-generated.
    base_username := lower(regexp_replace(
        coalesce(new.raw_user_meta_data ->> 'username', ''),
        '[^a-z0-9_]', '', 'g'
    ));

    if base_username is null or length(base_username) < 3 then
        base_username := 'user';
    end if;
    base_username := left(base_username, 24);

    -- Duplicate username never blocks signup: append a random suffix.
    candidate := base_username;
    while exists (select 1 from public.profiles where username = candidate) loop
        candidate := base_username || '_' || substr(md5(random()::text), 1, 4);
    end loop;

    insert into public.profiles (id, username, full_name, avatar_url)
    values (
        new.id,
        candidate,
        new.raw_user_meta_data ->> 'full_name',
        new.raw_user_meta_data ->> 'avatar_url'
    )
    on conflict (id) do nothing;

    insert into public.private_profiles (id, email, phone)
    values (
        new.id,
        new.email,
        nullif(new.raw_user_meta_data ->> 'phone', '')
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. notify_new_message: tambahkan header x-internal-key dari app_secrets.
-- ---------------------------------------------------------------------------
create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_url      text := 'https://ytmkhmsndfwmjlfyxiiw.supabase.co/functions/v1/send-push';
    v_key      text;
    v_internal text;
    v_sender_name text;
begin
    -- Anon key untuk Authorization (publik by design).
    v_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0bWtobXNuZGZ3bWpsZnl4aWl3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwOTk5NzksImV4cCI6MjEwMjY3NTk3OX0.klvdt6g4MhTKusBhuGKxPrjUQHt8DsOsTVXFH1dF9zo';

    -- Shared secret untuk endpoint push.
    select value into v_internal
        from public.app_secrets
        where name = 'push_internal_key'
        limit 1;
    if v_internal is null then
        return new;  -- belum dikonfigurasi: jangan gagalkan insert chat.
    end if;

    -- Nama pengirim sebagai judul notifikasi.
    select coalesce(nullif(full_name, ''), username, 'Zenlook')
      into v_sender_name
      from profiles
      where id = new.sender_id;

    perform net.http_post(
        url := v_url,
        headers := jsonb_build_object(
            'Content-Type',    'application/json',
            'Authorization',   'Bearer ' || v_key,
            'x-internal-key',  v_internal
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
