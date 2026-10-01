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
-- Nearby Users Feature Implementation (Fixed)
-- Run these in Supabase SQL Editor
-- ============================================

-- 1. Enable PostGIS extension (if not already enabled)
create extension if not exists postgis;

-- 2. Create table to track nearby alert history (for cooldown)
create table if not exists public.nearby_alert_history (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    nearby_user_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique(user_id, nearby_user_id) -- Prevent duplicate entries for same pair
);

-- 3. Create or replace the trigger function
create or replace function public.check_nearby_users()
returns trigger as $$
declare
    v_user_nearby_enabled boolean;
    v_user_alert_radius integer;
    v_user_location geography;
    v_nearby_count integer;
begin
    -- Exit if this is a location delete (not insert/update)
    if tg_op = 'DELETE' then
        return old;
    end if;

    -- Get the user's settings and current location
    select 
        p.nearby_alerts_enabled,
        p.nearby_alert_radius,
        ST_SetSRID(ST_MakePoint(new.longitude, new.latitude), 4326)::geography
    into 
        v_user_nearby_enabled,
        v_user_alert_radius,
        v_user_location
    from public.profiles p
    where p.id = new.user_id;

    -- If nearby alerts are disabled for this user, do nothing
    if not v_user_nearby_enabled then
        return new;
    end if;

    -- Check for users who have nearby alerts enabled and are within radius
    insert into public.nearby_alert_history (user_id, nearby_user_id, created_at)
    select 
        p.id as user_id,          -- The user who should receive alert
        new.user_id as nearby_user_id, -- The user whose location triggered the alert
        now()
    from public.profiles p
    join public.private_profiles pp on p.id = pp.id
    join public.locations l on p.id = l.user_id
    where 
        p.nearby_alerts_enabled = true
        and p.id != new.user_id  -- Not self
        and ST_DWithin(
            ST_SetSRID(ST_MakePoint(l.longitude, l.latitude), 4326)::geography, 
            v_user_location, 
            v_user_alert_radius::double precision
        )
        and not exists ( -- Enforce 30-minute cooldown
            select 1 from public.nearby_alert_history nah
            where 
                nah.user_id = p.id
                and nah.nearby_user_id = new.user_id
                and nah.created_at > now() - interval '30 minutes'
        );

    get diagnostics v_nearby_count = row_count;

    -- Optional: Log for debugging (remove in production)
    -- raise notice 'Nearby check: % alerts triggered for user %', v_nearby_count, new.user_id;

    return new;
end;
$$ language plpgsql security definer;

-- 4. Attach trigger to locations table
drop trigger if exists nearby_alert_trigger on public.locations;
create trigger nearby_alert_trigger
after insert or update of latitude, longitude on public.locations
for each row execute function public.check_nearby_users();

-- 5. Create index for performance (critical for ST_DWithin)
-- Index on the geography point computed from latitude/longitude
create index if not exists idx_locations_geography 
on public.locations using gist (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography);

-- 6. (Optional) Create view for easy frontend consumption
create or replace view public.nearby_alerts_view as
select 
    nah.id,
    nah.user_id as alert_receiver_id,
    p_receiver.username as alert_receiver_username,
    p_receiver.avatar_url as alert_receiver_avatar,
    nah.nearby_user_id as nearby_user_id,
    p_nearby.username as nearby_user_username,
    p_nearby.avatar_url as nearby_user_avatar,
    nah.created_at
from public.nearby_alert_history nah
join public.profiles p_receiver on nah.user_id = p_receiver.id
join public.profiles p_nearby on nah.nearby_user_id = p_nearby.id
order by nah.created_at desc;

-- ============================================
-- Instructions:
-- 1. Run this entire script in Supabase SQL Editor
-- 2. Test by updating a user's location and checking nearby_alert_history
-- 3. For Flutter: query nearby_alerts_view to show notifications
-- ============================================