-- ============================================================================
-- ARCHIVED — SUPERSEDED. JANGAN DIJALANKAN.
-- Fitur Nearby Alert diimplementasikan ulang TANPA PostGIS di
-- backend/schema.sql (tabel nearby_alert_cooldown + fungsi notify_nearby_users
-- + pg_net push). File ini memakai pendekatan LAMA berbasis PostGIS
-- (nearby_alert_history / check_nearby_users / nearby_alerts_view) dan memuat
-- pernyataan DROP yang dapat merusak database bila dijalankan.
-- Disimpan hanya sebagai riwayat. Sumber kebenaran: backend/schema.sql.
-- ============================================================================

-- ============================================
-- Nearby Users Feature - Safe SQL for Supabase
-- Copy paste everything below into Supabase SQL Editor and RUN
-- ============================================

-- 0. Safety: drop existing objects if they exist (ignore errors if not found)
drop trigger if exists nearby_alert_trigger on public.locations;
drop function if exists public.check_nearby_users();
drop table if exists public.nearby_alert_history;
drop index if exists idx_locations_geography;
drop view if exists public.nearby_alerts_view;

-- 1. Enable PostGIS extension (if not already)
create extension if not exists postgis;

-- 2. Table to store alert history (for cooldown)
create table public.nearby_alert_history (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    nearby_user_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique(user_id, nearby_user_id) -- prevent duplicate alerts for same pair
);

-- 3. Trigger function: fires after location insert/update
create or replace function public.check_nearby_users()
returns trigger as $$
declare
    v_enabled   boolean;
    v_radius    integer;
    v_user_geo  geography;
begin
    -- If this is a delete operation, ignore
    if tg_op = 'DELETE' then
        return old;
    end if;

    -- Fetch user's nearby alert settings and current location as geography
    select 
        p.nearby_alerts_enabled,
        p.nearby_alert_radius,
        ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography
    into 
        v_enabled,
        v_radius,
        v_user_geo
    from public.profiles p
    where p.id = new.user_id;

    -- If user has disabled nearby alerts, do nothing
    if not v_enabled then
        return new;
    end if;

    -- Insert alerts for other users who have alerts enabled and are within radius
    insert into public.nearby_alert_history (user_id, nearby_user_id, created_at)
    select 
        p.id as user_id,               -- who should get the alert
        new.user_id as nearby_user_id, -- whose location triggered it
        now()
    from public.profiles p
    join public.private_profiles pp on p.id = pp.id
    join public.locations l on p.id = l.user_id
    where 
        p.nearby_alerts_enabled = true
        and p.id != new.user_id  -- not self
        and ST_DWithin(
            ST_SetSRID(ST_MakePoint(l.longitude, l.latitude), 4326)::geography,
            v_user_geo,
            v_radius::double precision
        )
        and not exists ( -- enforce 30‑minute cooldown per pair
            select 1 from public.nearby_alert_history nah
            where 
                nah.user_id = p.id
                and nah.nearby_user_id = new.user_id
                and nah.created_at > now() - interval '30 minutes'
        );

    return new;
end;
$$ language plpgsql security definer;

-- 4. Attach the trigger to the locations table
create trigger nearby_alert_trigger
after insert or update of latitude, longitude on public.locations
for each row execute function public.check_nearby_users();

-- 5. Spatial index for fast ST_DWithin queries
create index if not exists idx_locations_geography
on public.locations using gist (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography);

-- 6. Optional convenience view for frontend
create or replace view public.nearby_alerts_view as
select 
    nah.id,
    nah.user_id as alert_receiver_id,
    pr.username as alert_receiver_username,
    pr.avatar_url as alert_receiver_avatar,
    nah.nearby_user_id as nearby_user_id,
    pn.username as nearby_user_username,
    pn.avatar_url as nearby_user_avatar,
    nah.created_at
from public.nearby_alert_history nah
join public.profiles pr on nah.user_id = pr.id
join public.profiles pn on nah.nearby_user_id = pn.id
order by nah.created_at desc;

-- ============================================
-- Verification steps (run after the script):
-- 1. SELECT * FROM pg_extension WHERE extname = 'postgis';
-- 2. \d+ public.locations   --> should show nearby_alert_trigger
-- 3. \df public.check_nearby_users*
-- 4. SELECT * FROM public.nearby_alert_history LIMIT 5;
-- 5. Test: update a user's location, then check if alerts appear for nearby users.
-- ============================================