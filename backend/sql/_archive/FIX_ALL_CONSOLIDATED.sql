-- ============================================================================
-- CONSOLIDATED FIX — Jalankan sekali saja di SQL Editor.
-- Berisi: tambah kolom security_code, fix trigger handle_new_user
-- (termasuk security_code + username sanitization), dan buat /
-- grant fungsi-fungsi RPC yang dibutuhkan login & lupa password.
-- ============================================================================

-- 1. Tambah kolom security_code jika belum ada
ALTER TABLE public.private_profiles
    ADD COLUMN IF NOT EXISTS security_code text;

-- 2. Replace trigger handle_new_user — versi LENGKAP:
--    • sanitize & dedupe username
--    • simpan full_name, avatar_url, phone
--    • simpan security_code dari metadata signup
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
    on conflict (id) do update
        set username    = candidate,
            full_name   = coalesce(new.raw_user_meta_data ->> 'full_name', profiles.full_name),
            avatar_url  = coalesce(new.raw_user_meta_data ->> 'avatar_url', profiles.avatar_url);

    insert into public.private_profiles (id, email, phone, security_code)
    values (
        new.id,
        coalesce(new.email, ''),
        coalesce(new.raw_user_meta_data ->> 'phone', ''),
        coalesce(new.raw_user_meta_data ->> 'security_code', '')
    )
    on conflict (id) do update
        set email         = coalesce(new.email, ''),
            phone         = coalesce(new.raw_user_meta_data ->> 'phone', ''),
            security_code = coalesce(new.raw_user_meta_data ->> 'security_code', '');

    return new;
end;
$$;

-- 3. Fungsi RPC: cari email by username (untuk login)
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

-- 4. Fungsi RPC: verifikasi security code (untuk lupa password)
create or replace function public.verify_security_code(
    p_username text,
    p_code text
)
returns uuid
language sql
security definer
set search_path = public
as $$
    select pp.id
    from public.profiles p
    join public.private_profiles pp on pp.id = p.id
    where lower(p.username) = lower(p_username)
      and pp.security_code = p_code
    limit 1;
$$;

grant execute on function public.verify_security_code(text, text) to anon;
grant execute on function public.verify_security_code(text, text) to authenticated;
