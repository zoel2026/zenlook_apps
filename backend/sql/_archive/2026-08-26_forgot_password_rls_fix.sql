-- ============================================================================
-- Fix: Lupa Password harus bisa jalan saat user belum login.
-- profiles punya RLS yang hanya boleh dibaca owner / authenticated,
-- sehingga query .from('profiles') di forgot_password_screen selalu
-- return kosong untuk user yang sudah sign-out.
--
-- Solusi: buat RPC security-definer yang return user_id by username,
-- grant ke anon supaya bisa dipanggil tanpa session.
-- ============================================================================

-- 1. Function: ambil user_id berdasarkan username (untuk lupa password)
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

grant execute on function public.get_user_id_by_username(text) to anon;
grant execute on function public.get_user_id_by_username(text) to authenticated;
