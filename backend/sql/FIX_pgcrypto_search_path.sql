-- ============================================================================
-- FIX: "function gen_salt(unknown) does not exist" saat signup (500)
-- Project: pxifrxnkqxgzcgopgtvm
--
-- Penyebab: pgcrypto (crypt/gen_salt) terinstall di schema 'extensions',
-- tetapi fungsi-fungsi di bawah memakai SET search_path = 'public' sehingga
-- tidak bisa menemukan gen_salt()/crypt().
-- Fix: tambahkan schema 'extensions' pada search_path tiap fungsi.
--
-- Jalankan SEKALI di: Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================================

-- 1) handle_new_user (penyebab error signup)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
declare
    base_username text;
    candidate     text;
    raw_code      text;
begin
    base_username := lower(regexp_replace(
        coalesce(new.raw_user_meta_data ->> 'username', ''),
        '[^a-z0-9_]', '', 'g'
    ));

    if base_username is null or length(base_username) < 3 then
        base_username := 'user';
    end if;
    base_username := left(base_username, 24);

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

    raw_code := nullif(new.raw_user_meta_data ->> 'security_code', '');

    insert into public.private_profiles (id, email, phone, security_code)
    values (
        new.id,
        coalesce(new.email, ''),
        coalesce(new.raw_user_meta_data ->> 'phone', ''),
        case when raw_code is not null then crypt(raw_code, gen_salt('bf')) else null end
    )
    on conflict (id) do update
        set email         = coalesce(new.email, ''),
            phone         = coalesce(new.raw_user_meta_data ->> 'phone', ''),
            security_code = case
                when raw_code is not null then crypt(raw_code, gen_salt('bf'))
                else private_profiles.security_code
            end;

    return new;
end;
$$;

-- 2) set_security_code
CREATE OR REPLACE FUNCTION public.set_security_code(
    p_user_id uuid,
    p_code text
)
returns void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Tidak boleh mengubah kode keamanan orang lain';
    END IF;

    UPDATE public.private_profiles
    SET security_code = crypt(p_code, gen_salt('bf'))
    WHERE id = p_user_id;
END;
$$;

-- 3) verify_security_code
CREATE OR REPLACE FUNCTION public.verify_security_code(
    p_username text,
    p_code text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_user_id uuid;
    v_stored  text;
    v_ok      boolean;
BEGIN
    IF NOT public.check_rate_limit('verify_security_code', lower(p_username), 5, 900) THEN
        RAISE EXCEPTION 'Terlalu banyak percobaan. Coba lagi dalam 15 menit.'
            USING ERRCODE = 'too_many_requests';
    END IF;

    SELECT pp.id, pp.security_code INTO v_user_id, v_stored
    FROM public.profiles p
    JOIN public.private_profiles pp ON pp.id = p.id
    WHERE lower(p.username) = lower(p_username)
    LIMIT 1;

    IF v_user_id IS NULL OR v_stored IS NULL THEN
        RETURN NULL;
    END IF;

    v_ok := (v_stored = crypt(p_code, v_stored));

    IF NOT v_ok THEN
        RETURN NULL;
    END IF;

    RETURN v_user_id;
END;
$$;

-- 4) reset_password_with_code
CREATE OR REPLACE FUNCTION public.reset_password_with_code(
    p_user_id uuid,
    p_new_password text,
    p_security_code text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
    v_stored text;
    v_ok     boolean;
BEGIN
    IF NOT public.check_rate_limit('reset_password', p_user_id::text, 3, 900) THEN
        RAISE EXCEPTION 'Terlalu banyak percobaan. Coba lagi dalam 15 menit.'
            USING ERRCODE = 'too_many_requests';
    END IF;

    SELECT security_code INTO v_stored
    FROM public.private_profiles
    WHERE id = p_user_id;

    IF v_stored IS NULL THEN
        RAISE EXCEPTION 'User tidak ditemukan';
    END IF;

    v_ok := (v_stored = crypt(p_security_code, v_stored));

    IF NOT v_ok THEN
        RAISE EXCEPTION 'Kode keamanan salah';
    END IF;

    UPDATE auth.users
    SET encrypted_password = crypt(p_new_password, gen_salt('bf', 12))
    WHERE id = p_user_id;

    IF NOT found THEN
        RAISE EXCEPTION 'User tidak ditemukan';
    END IF;

    UPDATE public.private_profiles
    SET security_code = NULL
    WHERE id = p_user_id;
END;
$$;
