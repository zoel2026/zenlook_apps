# Spec: Premium — Nearby Radius Gate

## Tujuan
Menambahkan gating premium untuk fitur "scan nearby" (temukan user di sekitar) berdasarkan radius maksimum. Fitur sosial inti (friend, chat, wave, status, lokasi antar teman accepted) tetap gratis dan tidak dibatasi.

## Prinsip
- **Jangan gate teman.** Lokasi & interaksi antar teman `accepted` tetap penuh (sesuai RLS existing).
- **Hanya gate discovery.** Yang dibatasi hanya `get_nearby_users` (public nearby scan).
- **Hard cap.** Premium max radius 10 km. Free max radius 2 km.
- **Enforce di DB.** Validasi via RPC `get_nearby_users` (security definer), bukan hanya UI.
- **Minim invasif.** Tidak mengubah tabel existing besar, cukup `entitlements` + logika di RPC.

## Database (`backend/schema.sql`)

```sql
create table if not exists public.entitlements (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  tier text not null default 'free' check (tier in ('free','pro')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.entitlements enable row level security;

create policy "entitlements_select_own" on public.entitlements
  for select using (auth.uid() = user_id);

-- Helper: cek premium (berlaku jika tier pro dan belum expired)
create or replace function public.is_premium(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.entitlements e
    where e.user_id = p_user_id
      and e.tier = 'pro'
      and (e.expires_at is null or e.expires_at > now())
  );
$$;
grant execute on function public.is_premium(uuid) to anon, authenticated;

-- Update get_nearby_users: enforce max radius
-- Free max 2 km, Pro max 10 km
create or replace function public.get_nearby_users(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision default 2
)
returns table (...)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_max double precision := 2.0;
begin
  if v_uid is not null and public.is_premium(v_uid) then
    v_max := 10.0;
  end if;
  if p_radius_km is null or p_radius_km < 0.1 then p_radius_km := 1.0; end if;
  if p_radius_km > v_max then p_radius_km := v_max; end if;
  -- ... existing query ...
end;
$$;
```

Catatan: query existing (filter teman accepted? saat ini `get_nearby_users` mengembalikan non-teman dalam radius — discovery) tetap dipertahankan. Hanya clamp radius.

## Flutter

- `services/premium_service.dart`
  - `Future<bool> isPremium()` — cek entitlement milik sendiri
  - `maxNearbyRadiusFor(bool premium)` pure ? 10.0 vs 2.0
  - `radiusClamped(double requested, bool premium)` pure
- `screens/nearby_tab.dart` (jika ada) / UI scan: tampilkan info "Meningkatkan radius dengan Premium" bila mencoba > 2 km saat free
- `widgets/premium_banner.dart` opsional (ringan)
- i18n: `premium_nearby_limit`, `premium_upgrade_cta`, `premium_pro_badge`

## Testing
- Unit test pure (clamp)
- Tidak mengubah perilaku antar teman
- RLS: `entitlements` hanya select own

## Acceptance
- Free user: radius > 2 km di-clamp ke 2 km
- Pro user: radius > 10 km di-clamp ke 10 km
- Teman accepted tetap bisa akses penuh (tidak terganggu)
