-- ============================================================================
-- Security Code for Password Reset
-- Adds a 6-digit PIN to private_profiles for self-service password reset.
-- ============================================================================

-- 1. Tambah kolom security_code
ALTER TABLE public.private_profiles
    ADD COLUMN IF NOT EXISTS security_code text;

-- 1b. Sync handle_new_user dengan schema.sql: salin security_code dari
--     metadata signup ke private_profiles. Tanpa ini kode keamanan tidak
--     pernah tersimpan dan fitur lupa password tidak berfungsi.
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

    insert into public.private_profiles (id, email, phone, security_code)
    values (
        new.id,
        new.email,
        nullif(new.raw_user_meta_data ->> 'phone', ''),
        nullif(new.raw_user_meta_data ->> 'security_code', '')
    )
    on conflict (id) do nothing;

    return new;
end;
$$;

-- 2. Function: simpan security code saat registrasi
--    Guard: hanya boleh mengubah kode milik sendiri (auth.uid()).
--    Tanpa guard, user lain bisa menimpa kode korban -> account takeover.
create or replace function public.set_security_code(
    p_user_id uuid,
    p_code text
)
returns void
language sql
security definer
set search_path = public
as $$
    update public.private_profiles
    set security_code = p_code
    where id = p_user_id
      and p_user_id = auth.uid();
$$;

-- 3. Function: verifikasi security code + return user id
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

grant execute on function public.set_security_code(uuid, text) to authenticated;
grant execute on function public.verify_security_code(text, text) to anon;
grant execute on function public.verify_security_code(text, text) to authenticated;
