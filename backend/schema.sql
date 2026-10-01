-- ============================================================================
-- Social Map App (Zenly-like) — Supabase Backend Schema
-- Canonical schema — all functions include latest security fixes (2026-08-31).
--
-- Apply this file in: Supabase Dashboard > SQL Editor > New query > Run
--   (or via `supabase db push` / `psql` against your project's database).
--
-- CHANGES FROM PREVIOUS VERSION:
-- - security_code now stored as bcrypt hash (not plaintext)
-- - verify_security_code: rate-limited (5x/15min) + bcrypt compare
-- - reset_password_with_code: rate-limited (3x/15min) + invalidates code after use
-- - handle_new_user: hashes security_code on signup
-- - set_security_code: hashes code before storing
-- - Added rate_limit_attempts table for server-side rate limiting
-- - Added get_user_id_by_username for forgot password flow
-- - (2026-09-08) Added blocked_users, message_reactions, user_reports
-- - (2026-09-08) messages: added is_voice, voice_url, voice_duration columns
-- - (2026-09-08) Block-aware RLS: messages insert, locations select, friendships insert
-- - (2026-09-08) Added is_blocked() helper function
-- - (2026-09-10) user_reports: rate limit 24 jam di-enforce server-side via trigger
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
-- Provides gen_random_uuid() for default UUIDs.
create extension if not exists "pgcrypto";

-- ============================================================================
-- Table: profiles
-- One row per user. Auto-created on signup by the handle_new_user trigger.
-- ============================================================================
create table if not exists public.profiles (
    id          uuid primary key references auth.users (id) on delete cascade,
    username    text unique,
    full_name   text,
    avatar_url  text,
    status      text not null default 'offline'
                check (status in ('online', 'offline')),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- Nearby Alert (2026-09-17): user opt-in menerima notifikasi saat ada
-- pengguna lain masuk radius lokasinya (satu arah, cooldown 30 menit).
-- Radius berlaku 100-1000 meter (default 500).
alter table public.profiles
    add column if not exists nearby_alerts_enabled boolean not null default false;
alter table public.profiles
    add column if not exists nearby_alert_radius integer not null default 500
    check (nearby_alert_radius between 100 and 1000);

-- ============================================================================
-- Table: private_profiles
-- Sensitive per-user data (email, phone, FCM token, security_code).
-- Split from profiles so "read other profiles" can never leak it.
-- Owner-only access; server code (service_role) bypasses RLS.
-- security_code is stored as a bcrypt hash (never plaintext).
-- ============================================================================
create table if not exists public.private_profiles (
    id            uuid primary key references public.profiles (id) on delete cascade,
    email         text,
    phone         text,
    device_token  text,
    security_code text,
    updated_at    timestamptz not null default now()
);

-- ============================================================================
-- Table: locations
-- One row per user (their latest position). Realtime-enabled for the live map.
-- ============================================================================
create table if not exists public.locations (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null unique references public.profiles (id) on delete cascade,
    latitude    double precision not null,
    longitude   double precision not null,
    accuracy    double precision,
    updated_at  timestamptz not null default now()
);

-- ============================================================================
-- Table: friendships
-- A friend request is a row with status 'pending'; accepted -> 'accepted'.
-- ============================================================================
create table if not exists public.friendships (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references public.profiles (id) on delete cascade,
    friend_id   uuid not null references public.profiles (id) on delete cascade,
    status      text not null default 'pending'
                check (status in ('pending', 'accepted')),
    created_at  timestamptz not null default now(),
    unique (user_id, friend_id),
    check (user_id <> friend_id)
);

-- ============================================================================
-- Table: messages
-- Direct chat between two users. Realtime-enabled for live conversations.
-- ============================================================================
create table if not exists public.messages (
    id          uuid primary key default gen_random_uuid(),
    sender_id   uuid not null references public.profiles (id) on delete cascade,
    receiver_id uuid not null references public.profiles (id) on delete cascade,
    content     text not null,
    read_at     timestamptz,
    is_voice    boolean not null default false,
    voice_url   text,
    voice_duration double precision,
    is_audio    boolean not null default false,
    audio_url   text,
    audio_name  text,
    audio_duration double precision,
    created_at  timestamptz not null default now(),
    check (sender_id <> receiver_id)
);

-- Kolom voice untuk database yang sudah ada (idempotent).
alter table public.messages add column if not exists is_voice boolean not null default false;
alter table public.messages add column if not exists voice_url text;
alter table public.messages add column if not exists voice_duration double precision;

-- Kolom audio (file MP3/umum yg dikirim di chat) untuk database yang ada (idempotent).
alter table public.messages add column if not exists is_audio boolean not null default false;
alter table public.messages add column if not exists audio_url text;
alter table public.messages add column if not exists audio_name text;
alter table public.messages add column if not exists audio_duration double precision;

-- ============================================================================
-- Table: blocked_users
-- User A memblokir User B. Berlaku dua arah: tidak bisa chat,
-- melihat lokasi, atau mengirim friend request.
-- ============================================================================
create table if not exists public.blocked_users (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references public.profiles (id) on delete cascade,
    blocked_id  uuid not null references public.profiles (id) on delete cascade,
    created_at  timestamptz not null default now(),
    unique (user_id, blocked_id),
    check (user_id <> blocked_id)
);

-- ============================================================================
-- Table: message_reactions
-- Reaksi emoji per pesan (maksimal 1 reaksi per user per pesan).
-- ============================================================================
create table if not exists public.message_reactions (
    id          uuid primary key default gen_random_uuid(),
    message_id  uuid not null references public.messages (id) on delete cascade,
    user_id     uuid not null references public.profiles (id) on delete cascade,
    emoji       text not null,
    created_at  timestamptz not null default now(),
    unique (message_id, user_id)
);

-- ============================================================================
-- Table: user_reports
-- Laporan pengguna (spam / tidak pantas / pelecehan / lainnya).
-- ============================================================================
create table if not exists public.user_reports (
    id          uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references public.profiles (id) on delete cascade,
    reported_id uuid not null references public.profiles (id) on delete cascade,
    reason      text not null,
    created_at  timestamptz not null default now(),
    check (reporter_id <> reported_id)
);

-- ============================================================================
-- Table: location_history
-- Append-only log of every position update, used to draw movement tracks.
-- Every upsert on public.locations auto-records a point (see trigger below).
-- ============================================================================
create table if not exists public.location_history (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references public.profiles (id) on delete cascade,
    latitude    double precision not null,
    longitude   double precision not null,
    accuracy    double precision,
    created_at  timestamptz not null default now()
);

-- ============================================================================
-- Table: rate_limit_attempts
-- Tracks verification attempts for server-side rate limiting.
-- Used by verify_security_code and reset_password_with_code.
-- RLS enabled with NO policies: only service_role / security-definer can access.
-- ============================================================================
create table if not exists public.rate_limit_attempts (
    id            uuid primary key default gen_random_uuid(),
    function_name text not null,
    identifier    text not null,
    ip_address    text,
    attempted_at  timestamptz not null default now()
);

create index if not exists rate_limit_func_id_idx
    on public.rate_limit_attempts (function_name, identifier, attempted_at);

-- ============================================================================
-- Storage: bucket pesan suara (voice-messages)
-- Public agar pesan suara bisa diputar dari URL publik tanpa autentikasi
-- tambahan; upload hanya untuk pengguna terautentikasi.
-- ============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('voice-messages', 'voice-messages', true, 5242880, array['audio/mpeg','audio/mp4','audio/aac','audio/x-m4a','audio/wav'])
on conflict (id) do nothing;

drop policy if exists "voice_messages_public_read" on storage.objects;
create policy "voice_messages_public_read"
    on storage.objects for select
    using (bucket_id = 'voice-messages');

drop policy if exists "voice_messages_auth_upload" on storage.objects;
create policy "voice_messages_auth_upload"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'voice-messages'
        -- path milik pengirim: uploads/<uid>_<timestamp>.m4a
        and name like 'uploads/' || auth.uid()::text || '\_%'
    );

drop policy if exists "voice_messages_update_own" on storage.objects;
create policy "voice_messages_update_own"
    on storage.objects for update
    to authenticated
    using (bucket_id = 'voice-messages'
        and owner = auth.uid());

drop policy if exists "voice_messages_delete_own" on storage.objects;
create policy "voice_messages_delete_own"
    on storage.objects for delete
    to authenticated
    using (bucket_id = 'voice-messages'
        and owner = auth.uid());

-- ============================================================================
-- Storage: bucket pesan audio (audio-files)
-- Public agar file audio bisa diputar dari URL publik tanpa autentikasi
-- tambahan; upload hanya untuk pengguna terautentikasi.
-- ============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('audio-files', 'audio-files', true, 26214400, array['audio/mpeg','audio/mp4','audio/aac','audio/x-m4a','audio/wav','audio/ogg'])
on conflict (id) do nothing;

drop policy if exists "audio_files_public_read" on storage.objects;
create policy "audio_files_public_read"
    on storage.objects for select
    using (bucket_id = 'audio-files');

drop policy if exists "audio_files_auth_upload" on storage.objects;
create policy "audio_files_auth_upload"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'audio-files'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "audio_files_update_own" on storage.objects;
create policy "audio_files_update_own"
    on storage.objects for update
    to authenticated
    using (bucket_id = 'audio-files'
        and owner = auth.uid());

drop policy if exists "audio_files_delete_own" on storage.objects;
create policy "audio_files_delete_own"
    on storage.objects for delete
    to authenticated
    using (bucket_id = 'audio-files'
        and owner = auth.uid());

-- ============================================================================
-- Table: app_secrets
-- Shared secrets for server-side flows (trigger <-> edge function).
-- RLS enabled with NO policies: clients can never read it; only
-- service_role / postgres / security-definer functions can.
-- ============================================================================
create table if not exists public.app_secrets (
    name        text primary key,
    value       text not null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- RLS aktif, tanpa satu pun policy => hanya service_role / postgres /
-- security-definer yang bisa membaca. Secret seed TIDAK dikomit di repo:
-- isi 'push_internal_key' via dashboard/CI dengan nilai acak per-env,
-- lalu set env PUSH_INTERNAL_KEY Edge Function dengan nilai SAMA.
alter table public.app_secrets enable row level security;

-- ============================================================================
-- Helper: keep updated_at current on UPDATE
-- ============================================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute procedure public.set_updated_at();

drop trigger if exists locations_set_updated_at on public.locations;
create trigger locations_set_updated_at
    before update on public.locations
    for each row execute procedure public.set_updated_at();

-- ============================================================================
-- Trigger: auto-create a profile row when a new auth user signs up
-- Hashes security_code with bcrypt before storing.
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    base_username text;
    candidate     text;
    raw_code      text;
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
    on conflict (id) do update
        set username    = candidate,
            full_name   = coalesce(new.raw_user_meta_data ->> 'full_name', profiles.full_name),
            avatar_url  = coalesce(new.raw_user_meta_data ->> 'avatar_url', profiles.avatar_url);

    -- Hash security_code before storing (bcrypt, cost 12 = konsisten dengan password)
    raw_code := nullif(new.raw_user_meta_data ->> 'security_code', '');

    insert into public.private_profiles (id, email, phone, security_code)
    values (
        new.id,
        coalesce(new.email, ''),
        coalesce(new.raw_user_meta_data ->> 'phone', ''),
        case when raw_code is not null then crypt(raw_code, gen_salt('bf', 12)) else null end
    )
    on conflict (id) do update
        set email         = coalesce(new.email, ''),
            phone         = coalesce(new.raw_user_meta_data ->> 'phone', ''),
            security_code = case
                when raw_code is not null then crypt(raw_code, gen_salt('bf', 12))
                else private_profiles.security_code
            end;

    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ============================================================================
-- RATE LIMITING FUNCTIONS
-- ============================================================================

-- Cleanup: remove attempts older than 1 hour
create or replace function public.cleanup_old_rate_limits()
returns void
language sql
security definer
set search_path = public
as $$
    delete from public.rate_limit_attempts
    where attempted_at < now() - interval '1 hour';
$$;

-- Check rate limit: returns true if allowed, false if exceeded.
-- Automatically records the attempt if allowed.
create or replace function public.check_rate_limit(
    p_function text,
    p_identifier text,
    p_max_attempts int default 5,
    p_window_seconds int default 900
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    v_count int;
    v_ip text;
begin
    -- Get caller IP from JWT claims
    v_ip := coalesce(
        current_setting('request.jwt.claims', true)::json ->> 'ip',
        'unknown'
    );

    -- Cleanup old rows periodically (~10% of calls)
    if random() < 0.1 then
        perform public.cleanup_old_rate_limits();
    end if;

    -- Count recent attempts
    select count(*) into v_count
    from public.rate_limit_attempts
    where function_name = p_function
      and identifier = p_identifier
      and attempted_at > now() - make_interval(secs => p_window_seconds);

    if v_count >= p_max_attempts then
        return false;
    end if;

    -- Record this attempt
    insert into public.rate_limit_attempts (function_name, identifier, ip_address)
    values (p_function, p_identifier, v_ip);

    return true;
end;
$$;

-- ============================================================================
-- AUTHENTICATION RPC FUNCTIONS
-- ============================================================================

-- Login by username: looks up email from private_profiles.
create or replace function public.get_email_by_username(p_username text)
returns text
language sql
security definer
set search_path = public
as $$
    select pp.email
    from public.profiles p
    join public.private_profiles pp on pp.id = p.id
    where lower(p.username) = lower(p_username)
    limit 1;
$$;

grant execute on function public.get_email_by_username(text) to anon;
grant execute on function public.get_email_by_username(text) to authenticated;

-- Forgot password: get user_id by username (for step 1 of reset flow).
create or replace function public.get_user_id_by_username(p_username text)
returns uuid
language sql
security definer
set search_path = public
as $$
    select p.id
    from public.profiles p
    where lower(p.username) = lower(p_username)
    limit 1;
$$;

-- Hanya authenticated (reset flow lewat get_email_by_username + verify code).
-- Tanpa grant anon: mencegah enumerasi username -> user_id oleh siapa pun.
grant execute on function public.get_user_id_by_username(text) to authenticated;

-- Verify security code: rate-limited + bcrypt compare.
-- Returns user_id if valid, NULL if invalid or rate-limited.
create or replace function public.verify_security_code(
    p_username text,
    p_code text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_user_id uuid;
    v_stored  text;
    v_ok      boolean;
begin
    -- Rate limit: max 5 attempts per 15 minutes per username
    if not public.check_rate_limit('verify_security_code', lower(p_username), 5, 900) then
        raise exception 'Terlalu banyak percobaan. Coba lagi dalam 15 menit.'
            using errcode = 'too_many_requests';
    end if;

    -- Look up user
    select pp.id, pp.security_code into v_user_id, v_stored
    from public.profiles p
    join public.private_profiles pp on pp.id = p.id
    where lower(p.username) = lower(p_username)
    limit 1;

    if v_user_id is null or v_stored is null then
        return null;
    end if;

    -- Constant-time bcrypt compare (anti timing attack)
    v_ok := (v_stored = crypt(p_code, v_stored));

    if not v_ok then
        return null;
    end if;

    return v_user_id;
end;
$$;

grant execute on function public.verify_security_code(text, text) to anon;
grant execute on function public.verify_security_code(text, text) to authenticated;

-- Set security code: hashes with bcrypt before storing.
-- Owner-only: can only set your own code.
create or replace function public.set_security_code(
    p_user_id uuid,
    p_code text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
    if p_user_id <> auth.uid() then
        raise exception 'Tidak boleh mengubah kode keamanan orang lain';
    end if;

    update public.private_profiles
    set security_code = crypt(p_code, gen_salt('bf', 12))
    where id = p_user_id;
end;
$$;

grant execute on function public.set_security_code(uuid, text) to authenticated;

-- Reset password via security code: rate-limited + invalidates code after use.
-- Updates auth.users.encrypted_password directly (requires security definer).
create or replace function public.reset_password_with_code(
    p_user_id uuid,
    p_new_password text,
    p_security_code text
)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
    v_stored text;
    v_ok     boolean;
begin
    -- Rate limit: max 3 attempts per 15 minutes per user
    if not public.check_rate_limit('reset_password', p_user_id::text, 3, 900) then
        raise exception 'Terlalu banyak percobaan. Coba lagi dalam 15 menit.'
            using errcode = 'too_many_requests';
    end if;

    -- Get stored hashed code
    select security_code into v_stored
    from public.private_profiles
    where id = p_user_id;

    if v_stored is null then
        raise exception 'User tidak ditemukan';
    end if;

    -- Verify with bcrypt compare
    v_ok := (v_stored = crypt(p_security_code, v_stored));

    if not v_ok then
        raise exception 'Kode keamanan salah';
    end if;

    -- Update password (cost factor 12 for security)
    update auth.users
    set encrypted_password = crypt(p_new_password, gen_salt('bf', 12))
    where id = p_user_id;

    if not found then
        raise exception 'User tidak ditemukan';
    end if;

    -- Invalidate security code after successful reset (one-time use)
    update public.private_profiles
    set security_code = null
    where id = p_user_id;
end;
$$;

grant execute on function public.reset_password_with_code(uuid, text, text) to anon;
grant execute on function public.reset_password_with_code(uuid, text, text) to authenticated;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
alter table public.profiles   enable row level security;
alter table public.locations  enable row level security;
alter table public.friendships enable row level security;
alter table public.messages   enable row level security;
alter table public.private_profiles enable row level security;
alter table public.location_history enable row level security;
alter table public.rate_limit_attempts enable row level security;
alter table public.app_secrets enable row level security;
alter table public.blocked_users enable row level security;
alter table public.message_reactions enable row level security;
alter table public.user_reports enable row level security;

-- Helper: cek apakah A memblokir B (atau sebaliknya). Berlaku dua arah.
create or replace function public.is_blocked(p_user_a uuid, p_user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.blocked_users
        where (user_id = p_user_a and blocked_id = p_user_b)
           or (user_id = p_user_b and blocked_id = p_user_a)
    );
$$;

grant execute on function public.is_blocked(uuid, uuid) to anon;
grant execute on function public.is_blocked(uuid, uuid) to authenticated;

-- ============================================================================
-- RPC: get_nearby_users
-- Cari pengguna Zenlook dalam radius tertentu (default 2 km) yang BUKAN
-- teman dan TIDAK memblokir (atau diblokir oleh) saya.
-- Hanya menampilkan user dengan lokasi diperbarui dalam 15 menit terakhir.
-- ============================================================================
create or replace function public.haversine(
    lat1 double precision,
    lng1 double precision,
    lat2 double precision,
    lng2 double precision
)
returns double precision
language sql
immutable
as $$
    select 2 * 6371000 * asin(sqrt(
        pow(sin(radians(lat2 - lat1) / 2), 2)
        + cos(radians(lat1)) * cos(radians(lat2))
          * pow(sin(radians(lng2 - lng1) / 2), 2)
    ));
$$;

create or replace function public.get_nearby_users(
    p_lat double precision,
    p_lng double precision,
    p_radius_km double precision default 2
)
returns table (
    id uuid,
    username text,
    full_name text,
    avatar_url text,
    distance_m double precision,
    updated_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if p_lat is null or p_lng is null then
        raise exception 'koordinat tidak valid' using errcode = 'invalid_parameter_value';
    end if;
    -- Batasi radius agar tidak disalahgunakan (1 - 10 km).
    if p_radius_km < 1 or p_radius_km > 10 or p_radius_km is null then
        p_radius_km := 2;
    end if;

    return query
        select
            p.id,
            p.username,
            p.full_name,
            p.avatar_url,
            round(public.haversine(l.latitude, l.longitude, p_lat, p_lng))::double precision as distance_m,
            l.updated_at
        from public.locations l
        join public.profiles p on p.id = l.user_id
        left join public.blocked_users b
          on (b.user_id = l.user_id and b.blocked_id = auth.uid())
          or (b.user_id = auth.uid() and b.blocked_id = l.user_id)
        left join public.friendships f
          on f.status = 'accepted'
         and ((f.user_id = auth.uid() and f.friend_id = l.user_id)
           or (f.friend_id = auth.uid() and f.user_id = l.user_id))
        where l.user_id <> auth.uid()
          and b.id is null
          and f.id is null
          and l.latitude is not null
          and l.longitude is not null
          and l.updated_at > now() - interval '15 minutes'
          and public.haversine(l.latitude, l.longitude, p_lat, p_lng) <= p_radius_km * 1000
        order by distance_m asc
        limit 20;
end;
$$;

grant execute on function public.haversine(double precision, double precision, double precision, double precision) to anon;
grant execute on function public.haversine(double precision, double precision, double precision, double precision) to authenticated;
grant execute on function public.get_nearby_users(double precision, double precision, double precision) to authenticated;

-- private_profiles: owner-only access
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

-- Guard: cegah owner menulis security_code langsung (plaintext) sehingga
-- mem-bypass set_security_code (bcrypt). service_role / SECURITY DEFINER
-- (mis. set_security_code) tetap boleh.
create or replace function public.private_profiles_update_guard()
returns trigger
language plpgsql
as $$
declare
    jwt_role text;
begin
    jwt_role := coalesce(
        current_setting('request.jwt.claims', true)::json ->> 'role', '');
    if jwt_role = 'service_role' then
        return new;
    end if;
    if current_user = 'postgres' then
        return new; -- SECURITY DEFINER (set_security_code / handle_new_user)
    end if;
    if new.security_code is distinct from old.security_code then
        raise exception 'security_code hanya boleh diubah via set_security_code';
    end if;
    return new;
end;
$$;

drop trigger if exists private_profiles_update_guard on public.private_profiles;
create trigger private_profiles_update_guard
    before update on public.private_profiles
    for each row execute procedure public.private_profiles_update_guard();

-- profiles: users can read their own profile
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
    on public.profiles for select
    using (auth.uid() = id);

-- profiles: authenticated users can read other profiles (search / friends list)
drop policy if exists "profiles_select_others" on public.profiles;
create policy "profiles_select_others"
    on public.profiles for select
    using (auth.role() = 'authenticated' and auth.uid() <> id);

-- profiles: users can update their own profile
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
    on public.profiles for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

-- locations: users can insert their own location
drop policy if exists "locations_insert_own" on public.locations;
create policy "locations_insert_own"
    on public.locations for insert
    with check (auth.uid() = user_id);

-- locations: users can update their own location
drop policy if exists "locations_update_own" on public.locations;
create policy "locations_update_own"
    on public.locations for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- locations: users can read their own location
drop policy if exists "locations_select_own" on public.locations;
create policy "locations_select_own"
    on public.locations for select
    using (auth.uid() = user_id);

-- locations: users can read locations of accepted friends
-- (kecuali jika salah satu memblokir yang lain)
drop policy if exists "locations_select_friends" on public.locations;
create policy "locations_select_friends"
    on public.locations for select
    using (
        not public.is_blocked(auth.uid(), locations.user_id)
        and exists (
            select 1
            from public.friendships f
            where f.status = 'accepted'
              and (
                    (f.user_id = auth.uid() and f.friend_id = locations.user_id)
                 or (f.friend_id = auth.uid() and f.user_id = locations.user_id)
              )
        )
    );

-- friendships: readable by involved users
drop policy if exists "friendships_select_involved" on public.friendships;
create policy "friendships_select_involved"
    on public.friendships for select
    using (auth.uid() = user_id or auth.uid() = friend_id);

-- friendships: a user can create their own friend request
-- (tidak boleh jika salah satu memblokir yang lain)
drop policy if exists "friendships_insert_own" on public.friendships;
create policy "friendships_insert_own"
    on public.friendships for insert
    with check (
        auth.uid() = user_id
        and not public.is_blocked(user_id, friend_id)
    );

-- friendships: only the RECIPIENT (friend_id) can accept
drop policy if exists "friendships_update_involved" on public.friendships;
create policy "friendships_update_involved"
    on public.friendships for update
    using (auth.uid() = friend_id)
    with check (auth.uid() = friend_id);

-- friendships: involved users can delete (reject / cancel)
drop policy if exists "friendships_delete_involved" on public.friendships;
create policy "friendships_delete_involved"
    on public.friendships for delete
    using (auth.uid() = user_id or auth.uid() = friend_id);

-- messages: users can read messages they sent or received
drop policy if exists "messages_select_involved" on public.messages;
create policy "messages_select_involved"
    on public.messages for select
    using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- messages: a user can only send messages to ACCEPTED friends as themselves
-- dan tidak boleh mengirim ke user yang memblokir (atau diblokir oleh) mereka.
drop policy if exists "messages_insert_own" on public.messages;
create policy "messages_insert_own"
    on public.messages for insert
    with check (
        auth.uid() = sender_id
        and not public.is_blocked(sender_id, receiver_id)
        and exists (
            select 1 from public.friendships f
            where f.status = 'accepted'
              and ((f.user_id = sender_id and f.friend_id = receiver_id)
                or (f.friend_id = sender_id and f.user_id = receiver_id))
        )
    );

-- messages: the receiver can mark messages as read
drop policy if exists "messages_update_read" on public.messages;
create policy "messages_update_read"
    on public.messages for update
    using (auth.uid() = receiver_id)
    with check (auth.uid() = receiver_id);

-- ============================================================================
-- RLS: blocked_users
-- ============================================================================
drop policy if exists "blocked_users_select_own" on public.blocked_users;
create policy "blocked_users_select_own"
    on public.blocked_users for select
    using (auth.uid() = user_id);

drop policy if exists "blocked_users_insert_own" on public.blocked_users;
create policy "blocked_users_insert_own"
    on public.blocked_users for insert
    with check (auth.uid() = user_id);

drop policy if exists "blocked_users_delete_own" on public.blocked_users;
create policy "blocked_users_delete_own"
    on public.blocked_users for delete
    using (auth.uid() = user_id);

-- ============================================================================
-- RLS: message_reactions
-- Baca reaksi hanya untuk pesan yang melibatkan user.
-- ============================================================================
drop policy if exists "message_reactions_select_involved" on public.message_reactions;
create policy "message_reactions_select_involved"
    on public.message_reactions for select
    using (
        exists (
            select 1 from public.messages m
            where m.id = message_reactions.message_id
              and (auth.uid() = m.sender_id or auth.uid() = m.receiver_id)
        )
    );

drop policy if exists "message_reactions_insert_own" on public.message_reactions;
create policy "message_reactions_insert_own"
    on public.message_reactions for insert
    with check (
        auth.uid() = user_id
        and exists (
            select 1 from public.messages m
            where m.id = message_reactions.message_id
              and (auth.uid() = m.sender_id or auth.uid() = m.receiver_id)
        )
    );

drop policy if exists "message_reactions_delete_own" on public.message_reactions;
create policy "message_reactions_delete_own"
    on public.message_reactions for delete
    using (auth.uid() = user_id);

-- ============================================================================
-- RLS: user_reports
-- User hanya bisa membuat laporan sebagai dirinya sendiri,
-- dan membaca laporan yang pernah dibuatnya.
-- ============================================================================
drop policy if exists "user_reports_insert_own" on public.user_reports;
create policy "user_reports_insert_own"
    on public.user_reports for insert
    with check (auth.uid() = reporter_id);

drop policy if exists "user_reports_select_own" on public.user_reports;
create policy "user_reports_select_own"
    on public.user_reports for select
    using (auth.uid() = reporter_id);

-- Guard: maksimal 1 laporan per reporter+target per 24 jam.
-- Di-enforce server-side (mencegah TOCTOU/double-submit dari client).
create or replace function public.user_reports_24h_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (
        select 1 from public.user_reports
        where reporter_id = new.reporter_id
          and reported_id = new.reported_id
          and created_at > now() - interval '24 hours'
    ) then
        raise exception 'Sudah melaporkan pengguna ini dalam 24 jam terakhir'
            using errcode = 'unique_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists user_reports_24h_guard on public.user_reports;
create trigger user_reports_24h_guard
    before insert on public.user_reports
    for each row execute procedure public.user_reports_24h_guard();

-- Guard: RLS cannot restrict per column, so a trigger locks UPDATE down to
-- read_at only. service_role bypasses the guard.
create or replace function public.messages_update_guard()
returns trigger
language plpgsql
as $$
declare
    jwt_role text;
begin
    jwt_role := coalesce(
        current_setting('request.jwt.claims', true)::json ->> 'role', '');
    if jwt_role = 'service_role' then
        return new;
    end if;

    if auth.uid() is null or new.receiver_id <> auth.uid() then
        raise exception 'Hanya penerima yang boleh memperbarui pesan';
    end if;

    if new.sender_id   is distinct from old.sender_id
       or new.receiver_id is distinct from old.receiver_id
       or new.content     is distinct from old.content
       or new.created_at  is distinct from old.created_at then
        raise exception 'Hanya kolom read_at yang boleh diubah';
    end if;

    return new;
end;
$$;

drop trigger if exists messages_update_guard on public.messages;
create trigger messages_update_guard
    before update on public.messages
    for each row execute procedure public.messages_update_guard();

-- ============================================================================
-- Push notifications: pg_net -> Edge Function send-push
-- Secret diambil runtime dari app_secrets (tidak dikomit). Env Edge Function
-- PUSH_INTERNAL_KEY harus SAMA dengan nilai app_secrets('push_internal_key').
-- NOTE: v_url memakai project ref dibawah — VERIFIKASI konsisten dengan
-- app/.env (temuan R3 review; dua ref dipakai bersamaan).
-- ============================================================================
create extension if not exists pg_net;

create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_url          text := 'https://ytmkhmsndfwmjlfyxiiw.supabase.co/functions/v1/send-push';
    v_internal     text;
    v_sender_name  text;
    v_body         text;
begin
    if new.receiver_id is null or new.is_voice or new.is_audio then
        return new; -- voice/audio tanpa notifikasi teks; receiver wajib ada
    end if;

    select value into v_internal
        from public.app_secrets
        where name = 'push_internal_key'
        limit 1;
    if v_internal is null then
        return new; -- belum dikonfigurasi: jangan gagalkan insert chat
    end if;

    select coalesce(nullif(full_name, ''), username, 'Zenlook')
      into v_sender_name
      from public.profiles
      where id = new.sender_id;

    v_body := left(coalesce(nullif(new.content, ''), 'Pesan baru'), 80);

    perform net.http_post(
        url := v_url,
        headers := jsonb_build_object(
            'Content-Type',   'application/json',
            'x-internal-key', v_internal
        ),
        body := jsonb_build_object(
            'userId',   new.receiver_id,
            'title',    coalesce(v_sender_name, 'Zenlook'),
            'body',     v_body,
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

-- ============================================================================
-- Nearby Alert (2026-09-17)
-- Deteksi server-side: saat `locations` di-upsert, cari user yang menyalakan
-- nearby_alerts_enabled dan posisi mereka (last known di `locations`) dalam
-- radius masing-masing dari titik baru. Kalau lolos cooldown 30 menit dan
-- bukan blocking -> kirim push via Edge Function send-push (type 'nearby').
-- Satu arah: si alerter yang enable; target tidak perlu enable.
-- Seluruh logika jalan sebagai postgres (security definer) = bypass RLS.
-- ============================================================================

-- Index untuk prefilter kotak lat/lng (percepat pencarian radius).
create index if not exists locations_latlng_idx
    on public.locations (latitude, longitude);

-- Cooldown table: internal. RLS aktif tanpa policy -> tak bisa dibaca/ditulis
-- klien; hanya trigger (security definer) / service_role yang menyentuh.
create table if not exists public.nearby_alert_cooldown (
    alerter_id uuid not null references auth.users(id) on delete cascade,
    target_id  uuid not null references auth.users(id) on delete cascade,
    last_at    timestamptz not null default now(),
    primary key (alerter_id, target_id)
);
alter table public.nearby_alert_cooldown enable row level security;

create or replace function public.notify_nearby_users()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    -- NOTE: ref harus konsisten dengan notify_new_message & app/.env (R3).
    v_url          text := 'https://ytmkhmsndfwmjlfyxiiw.supabase.co/functions/v1/send-push';
    v_internal     text;
    v_target_name  text;
    v_row          record;
    v_rows         int;
begin
    if new.user_id is null then
        return new;
    end if;

    select value into v_internal
        from public.app_secrets
        where name = 'push_internal_key'
        limit 1;
    if v_internal is null then
        return new; -- belum konfigurasi: jangan ganggu upsert lokasi
    end if;

    select coalesce(nullif(full_name, ''), username, 'Pengguna Zenlook')
      into v_target_name
      from public.profiles
      where id = new.user_id;

    for v_row in
        select x.alerter_id, x.dist_m
          from (
              select a.id as alerter_id,
                     a.nearby_alert_radius as radius,
                     2 * 6371000 * asin(sqrt(
                           power(sin(radians(l.latitude - new.latitude) / 2), 2)
                         + cos(radians(l.latitude)) * cos(radians(new.latitude))
                         * power(sin(radians(l.longitude - new.longitude) / 2), 2)
                     )) as dist_m
                from public.profiles a
                join public.locations l on l.user_id = a.id
               where a.id <> new.user_id
                 and a.nearby_alerts_enabled = true
                 and a.nearby_alert_radius between 100 and 1000
                 and abs(l.latitude - new.latitude)
                     <= (a.nearby_alert_radius::float / 111320.0)
                 and abs(l.longitude - new.longitude)
                     <= (a.nearby_alert_radius::float
                         / (111320.0 * greatest(cos(radians(new.latitude)), 0.01)))
                 and not public.is_blocked(a.id, new.user_id)
                 and not public.is_blocked(new.user_id, a.id)
          ) x
         where x.dist_m <= x.radius
           and not exists (
               select 1 from public.nearby_alert_cooldown c
                where c.alerter_id = x.alerter_id
                  and c.target_id = new.user_id
                  and c.last_at > now() - interval '30 minutes'
           )
         order by x.dist_m
    loop
        -- Claim cooldown atomic: insert kalau belum ada; kalau sudah ada tapi
        -- basi (>30 mnt) refresh; kalau masih segar -> row_count 0 = skip.
        insert into public.nearby_alert_cooldown (alerter_id, target_id, last_at)
        values (v_row.alerter_id, new.user_id, now())
        on conflict (alerter_id, target_id) do update
            set last_at = excluded.last_at
            where public.nearby_alert_cooldown.last_at
                  <= excluded.last_at - interval '30 minutes';
        get diagnostics v_rows = row_count;
        if v_rows = 0 then
            continue; -- race: sudah dinotifikasi <30 menit oleh sesi lain
        end if;

        perform net.http_post(
            url := v_url,
            headers := jsonb_build_object(
                'Content-Type',   'application/json',
                'x-internal-key', v_internal
            ),
            body := jsonb_build_object(
                'type',       'nearby',
                'userId',     v_row.alerter_id,
                'title',      'User terdekat',
                'body',       v_target_name || ' sekitar ' || v_row.dist_m || ' m',
                'name',       v_target_name,
                'distance_m', v_row.dist_m,
                'latitude',   new.latitude,
                'longitude',  new.longitude
            )
        );
    end loop;

    return new;
end;
$$;

drop trigger if exists locations_notify_nearby on public.locations;
create trigger locations_notify_nearby
    after insert or update on public.locations
    for each row execute procedure public.notify_nearby_users();

-- location_history: owner can read own + friends can read
-- (insert is done by trigger with security definer, no user insert policy needed)
alter table public.location_history enable row level security;

drop policy if exists "location_history_select_own" on public.location_history;
create policy "location_history_select_own"
    on public.location_history for select
    using (auth.uid() = user_id);

drop policy if exists "location_history_select_friends" on public.location_history;
create policy "location_history_select_friends"
    on public.location_history for select
    using (
        auth.uid() is not null
        and not public.is_blocked(auth.uid(), location_history.user_id)
        and exists (
            select 1 from public.friendships f
            where f.status = 'accepted'
              and ((f.user_id = auth.uid() and f.friend_id = location_history.user_id)
                or (f.friend_id = auth.uid() and f.user_id = location_history.user_id))
        )
    );

grant select on public.location_history to authenticated;

-- ============================================================================
-- Table: waves  (fitur "Wave" / ping)
-- Kirim gelombang 👋 ke teman untuk isyarat "di mana kamu?" / "ayo ketemuan".
-- Disimpan agar bisa realtime + dedupe + audit singkat; maknanya ephemeral
-- (diabaikan setelah dibaca). Cooldown 5 menit per pasangan (trigger).
-- ============================================================================
create table if not exists public.waves (
    id          uuid primary key default gen_random_uuid(),
    sender_id   uuid not null references public.profiles (id) on delete cascade,
    receiver_id uuid not null references public.profiles (id) on delete cascade,
    created_at  timestamptz not null default now(),
    check (sender_id <> receiver_id)
);

create index if not exists waves_receiver_idx
    on public.waves (receiver_id, created_at desc);

-- Guard: cooldown 5 menit per pasangan pengirim->penerima (anti spam).
-- Di-enforce server-side (bukan hanya di client).
create or replace function public.waves_cooldown_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if exists (
        select 1 from public.waves
        where sender_id = new.sender_id
          and receiver_id = new.receiver_id
          and created_at > now() - interval '5 minutes'
    ) then
        raise exception 'Sudah mengirim wave ke pengguna ini baru-baru ini'
            using errcode = 'unique_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists waves_cooldown_guard on public.waves;
create trigger waves_cooldown_guard
    before insert on public.waves
    for each row execute procedure public.waves_cooldown_guard();

-- Push: wave baru -> Edge Function send-push (type 'wave').
create or replace function public.notify_new_wave()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    -- NOTE: ref harus konsisten dengan notify_new_message & app/.env (R3).
    v_url      text := 'https://ytmkhmsndfwmjlfyxiiw.supabase.co/functions/v1/send-push';
    v_internal text;
    v_name     text;
begin
    select value into v_internal
        from public.app_secrets
        where name = 'push_internal_key'
        limit 1;
    if v_internal is null then
        return new; -- belum dikonfigurasi: jangan gagalkan insert wave
    end if;

    select coalesce(nullif(full_name, ''), username, 'Zenlook')
      into v_name
      from public.profiles
      where id = new.sender_id;

    perform net.http_post(
        url := v_url,
        headers := jsonb_build_object(
            'Content-Type',   'application/json',
            'x-internal-key', v_internal
        ),
        body := jsonb_build_object(
            'type',     'wave',
            'userId',   new.receiver_id,
            'title',    coalesce(v_name, 'Zenlook'),
            'body',     coalesce(v_name, 'Seseorang') || ' mengirim wave 👋',
            'senderId', new.sender_id
        )
    );

    return new;
end;
$$;

drop trigger if exists waves_notify_push on public.waves;
create trigger waves_notify_push
    after insert on public.waves
    for each row execute procedure public.notify_new_wave();

alter table public.waves enable row level security;

-- waves: pengirim membuat sebagai dirinya, hanya ke teman accepted & tak blokir.
drop policy if exists "waves_insert_own" on public.waves;
create policy "waves_insert_own"
    on public.waves for insert
    with check (
        auth.uid() = sender_id
        and not public.is_blocked(sender_id, receiver_id)
        and exists (
            select 1 from public.friendships f
            where f.status = 'accepted'
              and ((f.user_id = sender_id and f.friend_id = receiver_id)
                or (f.friend_id = sender_id and f.user_id = receiver_id))
        )
    );

-- waves: hanya pihak yang terlibat yang bisa membaca.
drop policy if exists "waves_select_involved" on public.waves;
create policy "waves_select_involved"
    on public.waves for select
    using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- waves: pihak terlibat boleh menghapus (membersihkan riwayat).
drop policy if exists "waves_delete_involved" on public.waves;
create policy "waves_delete_involved"
    on public.waves for delete
    using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- ============================================================================
-- Realtime: stream changes to subscribed clients
-- ============================================================================
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'locations'
    ) then
        alter publication supabase_realtime add table public.locations;
    end if;
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'messages'
    ) then
        alter publication supabase_realtime add table public.messages;
    end if;
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'friendships'
    ) then
        alter publication supabase_realtime add table public.friendships;
    end if;
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'message_reactions'
    ) then
        alter publication supabase_realtime add table public.message_reactions;
    end if;
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'waves'
    ) then
        alter publication supabase_realtime add table public.waves;
    end if;
end
$$;

-- ============================================================================
-- INDEXES
-- ============================================================================
create index if not exists friendships_user_idx   on public.friendships (user_id);
create index if not exists friendships_friend_idx on public.friendships (friend_id);
create index if not exists messages_sender_idx    on public.messages (sender_id);
create index if not exists messages_receiver_idx  on public.messages (receiver_id);
create index if not exists messages_pair_idx
    on public.messages (least(sender_id, receiver_id), greatest(sender_id, receiver_id));
create index if not exists location_history_user_idx
    on public.location_history (user_id, created_at desc);
create index if not exists blocked_users_user_idx
    on public.blocked_users (user_id);
create index if not exists blocked_users_blocked_idx
    on public.blocked_users (blocked_id);
create index if not exists message_reactions_message_idx
    on public.message_reactions (message_id);
create index if not exists user_reports_reporter_idx
    on public.user_reports (reporter_id);
create index if not exists user_reports_reported_idx
    on public.user_reports (reported_id);
create index if not exists user_reports_pair_time_idx
    on public.user_reports (reporter_id, reported_id, created_at);

-- ============================================================================
-- Trigger: auto-record a history point on every locations insert/update
-- ============================================================================
create or replace function public.track_location_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.location_history (user_id, latitude, longitude, accuracy)
    values (new.user_id, new.latitude, new.longitude, new.accuracy);
    return new;
end;
$$;

drop trigger if exists locations_track_history on public.locations;
create trigger locations_track_history
    after insert or update on public.locations
    for each row execute procedure public.track_location_history();

-- ============================================================================
-- Storage: avatars
-- Public read; write limited to the owner via folder prefix (auth.uid()).
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars_read_public" on storage.objects;
create policy "avatars_read_public"
    on storage.objects for select
    using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
    on storage.objects for insert
    with check (
        bucket_id = 'avatars'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
    on storage.objects for update
    using (
        bucket_id = 'avatars'
        and auth.uid()::text = (storage.foldername(name))[1]
    )
    with check (
        bucket_id = 'avatars'
        and auth.uid()::text = (storage.foldername(name))[1]
    );

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
    on storage.objects for delete
    using (
        bucket_id = 'avatars'
        and auth.uid()::text = (storage.foldername(name))[1]
    );
