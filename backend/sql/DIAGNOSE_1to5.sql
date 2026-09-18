-- ============================================================================
-- DIAGNOSA 1/1 (hanya 5 query pertama)
-- Project: pxifrxnkqxgzcgopgtvm
-- Jalankan semua di bawah: Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================================

-- 1) Apakah extension pgcrypto / uuid-ossp terpasang?
select name, default_version, installed_version
from pg_available_extensions
where name in ('pgcrypto', 'uuid-ossp');

-- 2) Tabel yang dibutuhkan handle_new_user
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('profiles', 'private_profiles', 'locations', 'friendships', 'messages', 'blocked_users', 'rate_limit_attempts', 'app_secrets')
order by table_name;

-- 3) Kolom di profiles & private_profiles
select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles', 'private_profiles')
  and column_name in ('id','username','full_name','avatar_url','email','phone','security_code','status')
order by table_name, column_name;

-- 4) Trigger on_auth_user_created terpasang + definisinya?
select tgname, tgrelid::regclass,
       pg_get_triggerdef(oid) as trigger_def
from pg_trigger
where tgname = 'on_auth_user_created'
  and not tgisinternal;

-- 5) Isi fungsi handle_new_user yang sedang aktif (jika ada)
select n.nspname as schema,
       p.proname as function_name,
       pg_get_functiondef(p.oid) as func_def
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname = 'handle_new_user'
  and n.nspname = 'public';
