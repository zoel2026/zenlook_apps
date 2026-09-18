-- ============================================================================
-- DIAGNOSIS: "database error saving new user" (500 on signup)
-- Project: pxifrxnkqxgzcgopgtvm (yang dipakai app Flutter)
--
-- Jalankan di: Supabase Dashboard > SQL Editor > New query > Run
-- Hasil query di bawah akan menunjukkan status tabel & trigger yang dibutuhkan.
-- ============================================================================

-- 1) Apakah extension pgcrypto terpasang?
select name, default_version, installed_version
from pg_available_extensions
where name in ('pgcrypto', 'uuid-ossp');

-- 2) Apakah tabel-tabel yang dibutuhkan handle_new_user sudah ada?
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('profiles', 'private_profiles', 'locations', 'friendships', 'messages', 'blocked_users', 'rate_limit_attempts', 'app_secrets')
order by table_name;

-- 3) Kolom yang dipakai handle_new_user di profiles & private_profiles
select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles', 'private_profiles')
  and column_name in ('id','username','full_name','avatar_url','email','phone','security_code','status')
order by table_name, column_name;

-- 4) Apakah trigger on_auth_user_created terpasang, dan ke fungsi apa?
select tgname, tgrelid::regclass,
       pg_get_triggerdef(oid) as trigger_def
from pg_trigger
where tgname = 'on_auth_user_created'
  and not tgisinternal;

-- 5) Isi fungsi handle_new_user yang sedang aktif (jika ada)
select p.proname, pg_get_functiondef(p.oid) as func_def
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname = 'handle_new_user'
  and n.nspname = 'public';

-- 6) Ada berapa baris di auth.users (apakah user pernah bisa signup sebelumnya?)
select count(*) as total_auth_users from auth.users;
