-- ============================================================================
-- RPC: Reset password via security code (pengganti edge function).
-- Menggunakan supabase_admin untuk update auth.users tanpa session login.
-- ============================================================================

create or replace function public.reset_password_with_code(
    p_user_id uuid,
    p_new_password text,
    p_security_code text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_ok boolean;
begin
    -- 1. Verifikasi security code
    select exists(
        select 1 from public.private_profiles
        where id = p_user_id
          and security_code = p_security_code
    ) into v_ok;

    if not v_ok then
        raise exception 'Kode keamanan salah';
    end if;

    -- 2. Update password di auth.users
    update auth.users
    set encrypted_password = crypt(p_new_password, gen_salt('bf'))
    where id = p_user_id;

    if not found then
        raise exception 'User tidak ditemukan';
    end if;
end;
$$;

grant execute on function public.reset_password_with_code(uuid, text, text) to anon;
grant execute on function public.reset_password_with_code(uuid, text, text) to authenticated;
