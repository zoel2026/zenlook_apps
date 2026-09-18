# Social Map App — Zenlook

Zenly-like location sharing app with real-time map, friends, chat, and push notifications.

## Tech Stack

| Layer | Tech |
|-------|------|
| Frontend | Flutter (Dart) — Android / Windows / Web |
| Backend | Supabase (PostgreSQL + Edge Functions) |
| Database | Supabase PostgreSQL with RLS |
| Push | Firebase Cloud Messaging (FCM) via Edge Function |

## Project

| Setting | Value |
|---------|-------|
| Project URL | `https://ytmkhmsndfwmjlfyxiiw.supabase.co` |
| Project ref | `ytmkhmsndfwmjlfyxiiw` |

> Keep the **service role key** secret — it bypasses RLS. It is not committed here.

## Structure

```
├── app/                    # Flutter client
│   ├── lib/
│   │   ├── main.dart       # Entry point
│   │   ├── screens/        # UI screens (10 files)
│   │   ├── services/       # Location, FCM, push services
│   │   ├── widgets/        # Reusable UI components
│   │   └── utils/          # Helpers
│   └── pubspec.yaml
├── backend/
│   ├── schema.sql          # Canonical database schema (single source of truth; root copy = duplikat, pakai file ini)
│   ├── supabase/functions/ # Supabase Edge Functions (send-push) — satu-satunya root functions
│   ├── sql/                # Security patches + archive (jangan di-run ulang; lihat banner)
│   └── .env.example
└── docs/                   # Documentation, prototipe, FCM setup
```

## Quick Start

### Database

Apply `schema.sql` via Supabase Dashboard SQL Editor — contains all tables,
RLS policies, triggers, RPCs, indexes, and realtime config.

### Flutter App

```bash
cd app
cp .env.example .env       # Fill in Supabase keys
flutter pub get
flutter run
```

### Edge Function (Push)

```bash
cd backend
supabase functions deploy send-push
```

## Key Features

- Real-time location sharing with friends
- Friend request / accept / reject flow
- 1-on-1 chat with read receipts
- Push notifications via FCM
- Location history / movement tracks
- Login by username (no email needed)
- Forgot password via 6-digit security code

## Security

- RLS on all tables
- Sensitive data isolated in `private_profiles`
- Security codes stored as bcrypt hashes
- Rate limiting on verification and reset RPCs
- Message update guard (read_at only)
- Internal key protection for Edge Functions
