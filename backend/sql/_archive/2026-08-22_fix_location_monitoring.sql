-- ============================================================================
-- Patch: Fix monitoring posisi antar user (2026-08-22)
--
-- Gejala: user A tidak bisa melihat/memantau posisi user B di peta realtime.
-- Penyebab yang paling umum di project live:
--   1. Policy RLS "locations_select_friends" belum ada / versi lama, sehingga
--      SELECT lokasi teman diblokir (baik via embed PostgREST maupun Realtime).
--   2. Tabel locations/friendships belum masuk publication supabase_realtime,
--      sehingga update live tidak pernah sampai ke client.
--
-- Jalankan: Supabase Dashboard > SQL Editor > New query > paste > Run.
-- Semua statement idempotent — aman dijalankan berulang kali.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Verifikasi manual (opsional) — jalankan terpisah bila ingin mengecek:
-- SELECT policyname, cmd FROM pg_policies WHERE schemaname='public'
--   AND tablename IN ('locations','location_history');
-- SELECT * FROM pg_publication_tables WHERE pubname='supabase_realtime';
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Pastikan RLS aktif
-- ---------------------------------------------------------------------------
alter table public.locations        enable row level security;
alter table public.friendships      enable row level security;
alter table public.location_history enable row level security;

-- ---------------------------------------------------------------------------
-- 2. Policy SELECT lokasi sendiri + teman (dibuat ulang agar pasti terbaru)
-- ---------------------------------------------------------------------------
drop policy if exists "locations_select_own" on public.locations;
create policy "locations_select_own"
    on public.locations for select
    using (auth.uid() = user_id);

drop policy if exists "locations_select_friends" on public.locations;
create policy "locations_select_friends"
    on public.locations for select
    using (
        auth.uid() is not null
        and exists (
            select 1
            from public.friendships f
            where f.status = 'accepted'
              and (
                    (f.user_id = auth.uid() and f.friend_id = locations.user_id)
                 or (f.friend_id = auth.uid() and f.user_id = locations.user_id)
               )
        )
    );

drop policy if exists "location_history_select_own" on public.location_history;
create policy "location_history_select_own"
    on public.location_history for select
    using (auth.uid() = user_id);

drop policy if exists "location_history_select_friends" on public.location_history;
create policy "location_history_select_friends"
    on public.location_history for select
    using (
        auth.uid() is not null
        and exists (
            select 1 from public.friendships f
            where f.status = 'accepted'
              and ((f.user_id = auth.uid() and f.friend_id = location_history.user_id)
                or (f.friend_id = auth.uid() and f.user_id = location_history.user_id))
        )
    );

-- ---------------------------------------------------------------------------
-- 3. REPLICA IDENTITY FULL — supaya event UPDATE/DELETE Realtime mengirim
--    kolom lengkap (old_record/new record utuh) dan evaluasi RLS akurat.
-- ---------------------------------------------------------------------------
alter table public.locations   replica identity full;
alter table public.friendships replica identity full;

-- ---------------------------------------------------------------------------
-- 4. Pastikan ketiga tabel masuk publication supabase_realtime
-- ---------------------------------------------------------------------------
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public' and tablename = 'locations'
    ) then
        alter publication supabase_realtime add table public.locations;
    end if;

    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public' and tablename = 'messages'
    ) then
        alter publication supabase_realtime add table public.messages;
    end if;

    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public' and tablename = 'friendships'
    ) then
        alter publication supabase_realtime add table public.friendships;
    end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 5. Jaring pengaman grant (idempotent; Supabase biasanya sudah memberikan)
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;
grant select on public.locations        to authenticated;
grant select on public.friendships      to authenticated;
grant select on public.location_history to authenticated;
