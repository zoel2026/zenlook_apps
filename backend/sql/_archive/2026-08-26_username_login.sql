-- ============================================================================
-- Lookup email by username for login.
-- private_profiles is owner-only RLS, so a SECURITY DEFINER function is
-- needed to let unauthenticated callers resolve username → email.
-- ============================================================================

create or replace function public.get_email_by_username(p_username text)
returns text
language sql
security definer
set search_path = public
as $$
    select pp.email
    from public.profiles p
    join public.private_profiles pp on pp.id = p.id
    where lower(p.username) = lower(p_username)
    limit 1;
$$;

-- Allow anonymous (unauthenticated) callers to invoke this function.
grant execute on function public.get_email_by_username(text) to anon;
grant execute on function public.get_email_by_username(text) to authenticated;
