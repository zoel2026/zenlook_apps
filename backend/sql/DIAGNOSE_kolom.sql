-- Cek kolom yang ADA di tabel profiles & private_profiles (dibanding vs yang dipakai fungsi)
-- Project: pxifrxnkqxgzcgopgtvm

select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('profiles', 'private_profiles')
order by table_name, ordinal_position;
