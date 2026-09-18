-- Ringkas: satu query gabungan untuk cek kesehatan signup
-- Project: pxifrxnkqxgzcgopgtvm
-- Jalankan di SQL Editor, hasilnya SATU tabel berisi 1 baris.

select
  (select count(*) from pg_available_extensions
     where name='pgcrypto' and installed_version is not null) as pgcrypto_installed,
  (select count(*) from information_schema.tables
     where table_schema='public' and table_name='profiles') as profiles_table_exists,
  (select count(*) from information_schema.tables
     where table_schema='public' and table_name='private_profiles') as private_profiles_table_exists,
  (select count(*) from pg_trigger
     where tgname='on_auth_user_created' and not tgisinternal) as auth_trigger_exists;
