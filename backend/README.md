# ZenlyApps — Backend (Supabase)

Supabase backend for the Zenly-like social map app. Contains the database schema
(`schema.sql`), Row Level Security policies, triggers, realtime configuration,
and security-definer RPCs for authentication flows.

## Project

| Setting        | Value |
|----------------|-------|
| Project URL    | `https://ytmkhmsndfwmjlfyxiiw.supabase.co` |
| Project ref    | `ytmkhmsndfwmjlfyxiiw` |

> Keep the **service role key** secret — it bypasses RLS. It is never committed
> here (see [`.env.example`](./.env.example)).

## Files

- [`schema.sql`](./schema.sql) — **canonical** full schema (all tables, RLS,
  triggers, RPCs, indexes, realtime config, storage). This is the single source
  of truth — apply this file for fresh installs or to sync all changes.
- [`sql/2026-08-31_security_critical_fix.sql`](./sql/2026-08-31_security_critical_fix.sql) —
  Security patch for existing databases: rate limiting, hashed security_code,
  bcrypt verify, one-time-use reset. Run once if upgrading from pre-2026-08-31.
- [`sql/_archive/`](./sql/_archive/) — Old ad-hoc patches (superseded by
  `schema.sql`). Kept for reference only.
- [`.env.example`](./.env.example) — Supabase env placeholders.

## Tables

| Table | Purpose | Realtime |
|-------|---------|----------|
| `profiles` | Public user data (username, name, avatar, status) | No |
| `private_profiles` | Sensitive data (email, phone, FCM token, security_code) | No |
| `locations` | Latest GPS position per user | Yes |
| `friendships` | Friend requests / accepted relationships | Yes |
| `messages` | Direct 1-on-1 chat | Yes |
| `location_history` | Append-only movement track log | No |
| `rate_limit_attempts` | Server-side rate limiting tracking | No |
| `app_secrets` | Shared secrets for server-side flows | No |

## Security Features (2026-08-31)

- **Hashed security codes**: `security_code` stored as bcrypt hash (never plaintext)
- **Rate limiting**: `verify_security_code` max 5 attempts/15 min, `reset_password_with_code` max 3/15 min
- **Constant-time compare**: bcrypt comparison prevents timing attacks
- **One-time use**: security code invalidated after successful password reset
- **Private profiles**: sensitive data (email, phone, FCM token) isolated in separate table with owner-only RLS
- **Message update guard**: trigger prevents editing anything except `read_at`

## RPC Functions

| Function | Access | Purpose |
|----------|--------|---------|
| `get_email_by_username(text)` | anon + auth | Resolve username → email for login |
| `get_user_id_by_username(text)` | anon + auth | Resolve username → UUID for forgot password |
| `verify_security_code(text, text)` | anon + auth | Verify 6-digit PIN (rate-limited + bcrypt) |
| `set_security_code(uuid, text)` | auth only | Set/update own security code (hashed) |
| `reset_password_with_code(uuid, text, text)` | anon + auth | Reset password via security code (rate-limited) |

## Row Level Security (RLS)

RLS is enabled on all tables. Summary:

- **profiles**: read own + others (authenticated); update own only
- **private_profiles**: owner-only (select, insert, update)
- **locations**: insert/update own; read own + accepted friends
- **friendships**: read involved; insert own request; update (recipient only for accept); delete involved
- **messages**: read involved; insert own (to accepted friends only); update (receiver only, `read_at` only via trigger guard)
- **location_history**: read own + accepted friends (insert via trigger only)
- **rate_limit_attempts**: no policies (service_role only)
- **app_secrets**: no policies (service_role only)

## How to apply the schema

### Fresh install

Use `schema.sql` — it contains everything needed:

1. Open [Supabase Dashboard](https://supabase.com/dashboard) > SQL Editor
2. Paste contents of `schema.sql`
3. Click **Run**
4. Verify tables in Table Editor and policies in Authentication > Policies

### Upgrade existing database

If your database was created before 2026-08-31:

1. Run `schema.sql` first (idempotent — safe to re-run)
2. Then run `sql/2026-08-31_security_critical_fix.sql` to migrate existing
   plaintext security codes to bcrypt and add rate limiting

### Supabase CLI

```bash
supabase link --project-ref ytmkhmsndfwmjlfyxiiw
supabase db push
```

## Env / client setup

```bash
SUPABASE_URL=https://ytmkhmsndfwmjlfyxiiw.supabase.co
SUPABASE_ANON_KEY=<anon key>              # public, safe in the Flutter client
SUPABASE_SERVICE_ROLE_KEY=<service key>   # server-only, bypasses RLS — never expose
```

Copy [`.env.example`](./.env.example) to `.env` and fill in real values. `.env`
is git-ignored.
