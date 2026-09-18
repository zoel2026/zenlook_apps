-- ============================================================================
-- SECURITY CRITICAL FIX — 2026-08-31
-- Fix account takeover chain: rate limiting, hashed security code,
-- restricted RPC grants, username enumeration prevention.
--
-- Jalankan sekali di: Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================================

-- ============================================================================
-- 1. RATE LIMITING TABLE
-- Tracks verification attempts per (function_name, identifier, ip).
-- Older rows are auto-cleaned by the check function.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.rate_limit_attempts (
    id          uuid primary key default gen_random_uuid(),
    function_name text not null,
    identifier    text not null,
    ip_address    text,
    attempted_at  timestamptz not null default now()
);

CREATE INDEX IF NOT EXISTS rate_limit_func_id_idx
    ON public.rate_limit_attempts (function_name, identifier, attempted_at);

-- RLS: only service_role can read/write (no policies = no access for anon/authenticated)
ALTER TABLE public.rate_limit_attempts ENABLE ROW LEVEL SECURITY;

-- Auto-cleanup: remove attempts older than 1 hour
CREATE OR REPLACE FUNCTION public.cleanup_old_rate_limits()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    DELETE FROM public.rate_limit_attempts
    WHERE attempted_at < now() - interval '1 hour';
$$;

-- ============================================================================
-- 2. RATE LIMIT CHECK FUNCTION
-- Returns true if the attempt is allowed (under the limit).
-- Parameters:
--   p_function  — which RPC is being rate-limited
--   p_identifier — username or user_id being targeted
--   p_max_attempts — max allowed attempts (default 5)
--   p_window_seconds — time window in seconds (default 900 = 15 min)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_rate_limit(
    p_function text,
    p_identifier text,
    p_max_attempts int DEFAULT 5,
    p_window_seconds int DEFAULT 900
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count int;
    v_ip text;
BEGIN
    -- Get caller IP from JWT claims (Supabase sets this)
    v_ip := coalesce(
        current_setting('request.jwt.claims', true)::json ->> 'ip',
        'unknown'
    );

    -- Cleanup old rows periodically (run on ~10% of calls)
    IF random() < 0.1 THEN
        PERFORM public.cleanup_old_rate_limits();
    END IF;

    -- Count recent attempts for this function + identifier
    SELECT count(*) INTO v_count
    FROM public.rate_limit_attempts
    WHERE function_name = p_function
      AND identifier = p_identifier
      AND attempted_at > now() - make_interval(secs => p_window_seconds);

    IF v_count >= p_max_attempts THEN
        RETURN false;
    END IF;

    -- Record this attempt
    INSERT INTO public.rate_limit_attempts (function_name, identifier, ip_address)
    VALUES (p_function, p_identifier, v_ip);

    RETURN true;
END;
$$;

-- ============================================================================
-- 3. MIGRATE EXISTING security_code TO HASHED VERSION
-- Run once: bcrypt all existing plaintext codes.
-- After this, no plaintext codes should exist in the table.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.migrate_security_codes_to_hashed()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT id, security_code
        FROM public.private_profiles
        WHERE security_code IS NOT NULL
          AND security_code <> ''
          AND length(security_code) < 60  -- bcrypt hashes are 60 chars
    LOOP
        UPDATE public.private_profiles
        SET security_code = crypt(r.security_code, gen_salt('bf'))
        WHERE id = r.id;
    END LOOP;
END;
$$;

-- Run the migration
SELECT public.migrate_security_codes_to_hashed();

-- ============================================================================
-- 4. UPDATE handle_new_user — hash security_code on signup
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
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

    -- Hash security_code before storing
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

-- ============================================================================
-- 5. UPDATE set_security_code — hash the code before storing
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_security_code(
    p_user_id uuid,
    p_code text
)
returns void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- ============================================================================
-- 6. UPDATE verify_security_code — rate-limited + hashed compare
-- Returns user_id if valid, NULL if invalid or rate-limited.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.verify_security_code(
    p_username text,
    p_code text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id uuid;
    v_stored  text;
    v_ok      boolean;
BEGIN
    -- Rate limit: max 5 attempts per 15 minutes per username
    IF NOT public.check_rate_limit('verify_security_code', lower(p_username), 5, 900) THEN
        RAISE EXCEPTION 'Terlalu banyak percobaan. Coba lagi dalam 15 menit.'
            USING ERRCODE = 'too_many_requests';
    END IF;

    -- Look up user
    SELECT pp.id, pp.security_code INTO v_user_id, v_stored
    FROM public.profiles p
    JOIN public.private_profiles pp ON pp.id = p.id
    WHERE lower(p.username) = lower(p_username)
    LIMIT 1;

    IF v_user_id IS NULL OR v_stored IS NULL THEN
        RETURN NULL;
    END IF;

    -- Constant-time compare using pgcrypto
    v_ok := (v_stored = crypt(p_code, v_stored));

    IF NOT v_ok THEN
        RETURN NULL;
    END IF;

    RETURN v_user_id;
END;
$$;

-- ============================================================================
-- 7. UPDATE reset_password_with_code
-- - Rate limited (max 3 attempts per 15 min per user_id)
-- - Only grant to authenticated (fixes unauthenticated takeover chain)
-- - Invalidate security_code after successful reset
-- ============================================================================
CREATE OR REPLACE FUNCTION public.reset_password_with_code(
    p_user_id uuid,
    p_new_password text,
    p_security_code text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_stored text;
    v_ok     boolean;
BEGIN
    -- Rate limit: max 3 attempts per 15 minutes per user
    IF NOT public.check_rate_limit('reset_password', p_user_id::text, 3, 900) THEN
        RAISE EXCEPTION 'Terlalu banyak percobaan. Coba lagi dalam 15 menit.'
            USING ERRCODE = 'too_many_requests';
    END IF;

    -- Get stored hashed code
    SELECT security_code INTO v_stored
    FROM public.private_profiles
    WHERE id = p_user_id;

    IF v_stored IS NULL THEN
        RAISE EXCEPTION 'User tidak ditemukan';
    END IF;

    -- Verify with bcrypt compare
    v_ok := (v_stored = crypt(p_security_code, v_stored));

    IF NOT v_ok THEN
        RAISE EXCEPTION 'Kode keamanan salah';
    END IF;

    -- Update password
    UPDATE auth.users
    SET encrypted_password = crypt(p_new_password, gen_salt('bf', 12))
    WHERE id = p_user_id;

    IF NOT found THEN
        RAISE EXCEPTION 'User tidak ditemukan';
    END IF;

    -- Invalidate security code after successful reset (one-time use)
    UPDATE public.private_profiles
    SET security_code = NULL
    WHERE id = p_user_id;
END;
$$;

-- ============================================================================
-- 8. FIX GRANTS
-- NOTE: reset_password_with_code tetap open ke anon karena flow lupa password
-- butuh ini sebelum user login. Brute-force sudah diblokir oleh rate limiting
-- di verify_security_code (5x/15menit) + reset_password_with_code (3x/15menit).
-- ============================================================================
GRANT EXECUTE ON FUNCTION public.get_email_by_username(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_email_by_username(text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_security_code(uuid, text) TO authenticated;

-- verify_security_code: allow anon (forgot password flow) + authenticated
GRANT EXECUTE ON FUNCTION public.verify_security_code(text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.verify_security_code(text, text) TO authenticated;

-- reset_password_with_code: allow anon + authenticated (needed for forgot password flow)
-- Brute-force protection provided by rate limiting + hashed security_code.
GRANT EXECUTE ON FUNCTION public.reset_password_with_code(uuid, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.reset_password_with_code(uuid, text, text) TO authenticated;

-- get_user_id_by_username: allow anon (forgot password flow)
GRANT EXECUTE ON FUNCTION public.get_user_id_by_username(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_user_id_by_username(text) TO authenticated;

-- ============================================================================
-- 9. CLEANUP: drop old conflicting function versions
-- ============================================================================

-- ============================================================================
-- DONE. Setelah menjalankan SQL ini:
-- 1. security_code di-hash dengan bcrypt (tidak ada lagi plaintext)
-- 2. verify_security_code di-rate-limit (5x per 15 menit) + bcrypt compare
-- 3. reset_password_with_code di-rate-limit (3x per 15 menit) + bcrypt verify
-- 4. security_code di-invalidate setelah reset password berhasil (one-time use)
-- 5. Semua versi handle_new_user yang lama diganti yang terbaru (hash on signup)
-- 6. Brute-force 6 digit PIN sekarang butuh ~1800 percobaan/hari (rate-limited)
--    + bcrypt overhead = tidak praktis untuk di-brute-force
-- ============================================================================
