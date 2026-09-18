-- Cek di schema mana fungsi crypt/gen_salt dari pgcrypto berada
select n.nspname as schema, p.proname as function_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname in ('crypt', 'gen_salt')
order by p.proname, n.nspname;

-- Cek schema default extension pgcrypto
select e.extname, n.nspname as ext_schema
from pg_extension e
join pg_namespace n on n.oid = e.extnamespace
where e.extname = 'pgcrypto';

-- Cek isi search_path saat ini (default user)
show search_path;
