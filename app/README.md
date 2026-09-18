# ZenlyApps — Flutter App (placeholder)

This folder will hold the Flutter frontend for the Zenly-like social map app.

> The actual Flutter project is generated in a later step
> (e.g. `flutter create app`). This README is a placeholder to reserve the
> directory and document the intended structure.

## Planned structure

```
app/
├── lib/
│   ├── main.dart              # app entry point
│   ├── services/              # Supabase client, auth, location streaming
│   ├── screens/               # map, friends, profile, sign-in
│   └── widgets/               # map markers, presence badges, etc.
├── pubspec.yaml               # dependencies (supabase_flutter, flutter_map, …)
└── android/ ios/ web/         # platform runners
```

## Key dependencies (planned)

- [`supabase_flutter`](https://pub.dev/packages/supabase_flutter) — auth + database + realtime.
- [`flutter_map`](https://pub.dev/packages/flutter_map) — OpenStreetMap map view.
- [`latlong2`](https://pub.dev/packages/latlong2) — coordinates for `flutter_map`.
- [`geolocator`](https://pub.dev/packages/geolocator) — device location updates.

## Environment

The Flutter app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` (see
[`../backend/.env.example`](../backend/.env.example)) at build time via
`--dart-define` or a `.env` loader. Never commit real keys.
