# CI/CD Setup untuk Zenlook Apps

## Overview

Dokumentasi ini menjelaskan setup CI/CD pipeline untuk otomasi testing, building, dan deployment Zenlook Apps.

## GitHub Actions Workflow

### 1. Setup Flutter CI (Testing & Analysis)

Buat file `.github/workflows/flutter-ci.yml`:

```yaml
name: Flutter CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  test:
    name: Test & Analyze
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
          channel: 'stable'
      
      - name: Install dependencies
        working-directory: ./app
        run: flutter pub get
      
      - name: Verify formatting
        working-directory: ./app
        run: dart format --output=none --set-exit-if-changed .
      
      - name: Analyze code
        working-directory: ./app
        run: flutter analyze
      
      - name: Run tests
        working-directory: ./app
        run: flutter test --coverage
      
      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./app/coverage/lcov.info
          fail_ci_if_error: false
```

### 2. Setup Android Build & Release

Buat file `.github/workflows/android-release.yml`:

```yaml
name: Android Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    name: Build Android APK & AAB
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Java
        uses: actions/setup-java@v3
        with:
          distribution: 'zulu'
          java-version: '17'
      
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
          channel: 'stable'
      
      - name: Create .env file
        working-directory: ./app
        run: |
          echo "SUPABASE_URL=${{ secrets.SUPABASE_URL }}" >> .env
          echo "SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}" >> .env
      
      - name: Install dependencies
        working-directory: ./app
        run: flutter pub get
      
      - name: Build APK
        working-directory: ./app
        run: flutter build apk --release
      
      - name: Build App Bundle
        working-directory: ./app
        run: flutter build appbundle --release
      
      - name: Upload APK
        uses: actions/upload-artifact@v3
        with:
          name: release-apk
          path: app/build/app/outputs/flutter-apk/app-release.apk
      
      - name: Upload AAB
        uses: actions/upload-artifact@v3
        with:
          name: release-aab
          path: app/build/app/outputs/bundle/release/app-release.aab
      
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            app/build/app/outputs/flutter-apk/app-release.apk
            app/build/app/outputs/bundle/release/app-release.aab
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### 3. Setup Windows Build (Optional)

Buat file `.github/workflows/windows-build.yml`:

```yaml
name: Windows Build

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    name: Build Windows
    runs-on: windows-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.x'
          channel: 'stable'
      
      - name: Enable Windows Desktop
        working-directory: ./app
        run: flutter config --enable-windows-desktop
      
      - name: Install dependencies
        working-directory: ./app
        run: flutter pub get
      
      - name: Build Windows
        working-directory: ./app
        run: flutter build windows --release
      
      - name: Archive Windows Build
        uses: actions/upload-artifact@v3
        with:
          name: windows-build
          path: app/build/windows/x64/runner/Release/
```

---

## GitHub Secrets Setup

Tambahkan secrets di GitHub repo: `Settings > Secrets and variables > Actions`

### Required Secrets:

```
SUPABASE_URL=https://ytmkhmsndfwmjlfyxiiw.supabase.co
SUPABASE_ANON_KEY=eyJhbGc...
```

### Optional (untuk signed APK):

```
ANDROID_KEYSTORE_BASE64=<base64 encoded keystore>
KEYSTORE_PASSWORD=your_password
KEY_ALIAS=upload
KEY_PASSWORD=your_key_password
```

---

## Supabase Edge Function Deployment

### Manual Deploy

```bash
cd backend
supabase functions deploy send-push --project-ref ytmkhmsndfwmjlfyxiiw
```

### Auto Deploy via GitHub Actions

Buat file `.github/workflows/supabase-deploy.yml`:

```yaml
name: Deploy Supabase Functions

on:
  push:
    branches: [ main ]
    paths:
      - 'backend/supabase/functions/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest
      
      - name: Deploy Edge Functions
        working-directory: ./backend
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
        run: |
          supabase functions deploy send-push --project-ref ytmkhmsndfwmjlfyxiiw
```

**Setup:**
1. Dapatkan access token: `supabase login`
2. Tambahkan `SUPABASE_ACCESS_TOKEN` ke GitHub Secrets

---

## Database Migration Strategy

### Saat ini:
Schema di-apply manual via Supabase Dashboard SQL Editor.

### Rekomendasi untuk Production:

**1. Supabase CLI Migration:**

```bash
# Init project
cd backend
supabase init

# Link ke project
supabase link --project-ref ytmkhmsndfwmjlfyxiiw

# Generate migration dari schema.sql
supabase db diff -f initial_schema

# Apply migration
supabase db push

# Future changes
supabase db diff -f add_new_feature
supabase db push
```

**2. Version Control:**
- Semua migration di-commit ke git
- CI/CD auto-apply migration pada merge ke main
- Rollback tersedia via migration history

---

## Pre-deployment Checklist

### Flutter App

- [ ] `flutter analyze` bersih
- [ ] `flutter test` semua lulus
- [ ] `.env` tidak di-commit (ada di `.gitignore`)
- [ ] Version bump di `pubspec.yaml` (1.0.0+1 → 1.0.1+2)
- [ ] Update `CHANGELOG.md`
- [ ] Test di real device (Android/Windows)
- [ ] Build release: `flutter build apk --release`

### Backend

- [ ] Schema SQL terbaru di-apply di production DB
- [ ] Edge Functions deployed & tested
- [ ] Environment variables set di Supabase Dashboard
- [ ] `PUSH_INTERNAL_KEY` sama di DB (`app_secrets`) dan Edge Function env
- [ ] RLS policies verified
- [ ] Rate limiting tested

### Map Tiles

- [ ] Tile provider dipilih (Mapbox/Maptiler/Stadia)
- [ ] API key tersimpan di secrets (production)
- [ ] Usage monitoring disetup
- [ ] Fallback handling jika tile server down

### Firebase (FCM)

- [ ] `google-services.json` di-download dari Firebase Console
- [ ] FCM server key di Supabase Edge Function env
- [ ] Test push notification end-to-end
- [ ] Notification channel configured (Android)

---

## Monitoring & Alerts

### 1. Sentry (Error Tracking)

```yaml
# pubspec.yaml
dependencies:
  sentry_flutter: ^7.0.0

# main.dart
await SentryFlutter.init(
  (options) {
    options.dsn = 'YOUR_SENTRY_DSN';
    options.tracesSampleRate = 1.0;
  },
  appRunner: () => runApp(MyApp()),
);
```

### 2. Firebase Crashlytics

```yaml
dependencies:
  firebase_crashlytics: ^3.0.0

# main.dart
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
```

### 3. Supabase Metrics

Monitor via Supabase Dashboard:
- Database performance
- Edge Function invocations
- Storage usage
- Realtime connections

---

## Deployment Workflow (Production)

### 1. Development

```bash
git checkout -b feature/new-feature
# ... develop & test locally
flutter test
git commit -m "Add new feature"
git push origin feature/new-feature
```

### 2. Pull Request

- GitHub Actions auto-run tests
- Review kode
- Merge setelah tests lulus

### 3. Release

```bash
# Update version
# pubspec.yaml: version: 1.0.1+2

git tag v1.0.1
git push origin v1.0.1

# GitHub Actions auto-build & create release
```

### 4. Deploy Database (jika ada perubahan schema)

```bash
cd backend
supabase db push --project-ref ytmkhmsndfwmjlfyxiiw
```

### 5. Deploy Edge Functions (jika ada perubahan)

```bash
cd backend
supabase functions deploy send-push --project-ref ytmkhmsndfwmjlfyxiiw
```

---

## Rollback Strategy

### App

- Download APK versi sebelumnya dari GitHub Releases
- Deploy ke Play Store/distribute manual

### Database

```bash
# Lihat migration history
supabase db migrations list

# Rollback ke migration sebelumnya
supabase db migrations repair --status reverted
```

### Edge Functions

```bash
# Deploy versi sebelumnya dari git history
git checkout v1.0.0
cd backend
supabase functions deploy send-push
```

---

## Estimasi Biaya Bulanan (Production)

| Service | Free Tier | Paid (Estimate) |
|---------|-----------|-----------------|
| Supabase | 500MB DB, 1GB storage, 2GB bandwidth | $25/mo (Pro) |
| Firebase (FCM) | Unlimited | Free |
| Map Tiles (Stadia) | 200k requests | $49/mo (1M) |
| GitHub Actions | 2000 min/mo | $0.008/min |
| Sentry | 5k events/mo | $26/mo (Team) |
| VPS (optional) | - | $20/mo |

**Total untuk MVP:** $0 (dengan free tiers)
**Total untuk 1000+ DAU:** ~$100-150/mo

---

## Next Steps

1. Setup GitHub Actions workflows (copy dari docs ini)
2. Tambahkan secrets di GitHub repo
3. Test CI pipeline dengan dummy commit
4. Setup Sentry/Crashlytics untuk error tracking
5. Migrate dari OSM tiles ke Stadia Maps
6. Deploy edge function via CI/CD
7. Setup staging environment (optional: Supabase project terpisah)

---

**Catatan:**
CI/CD adalah investasi jangka panjang yang menghemat waktu dan mengurangi human error. Setup awal membutuhkan 2-4 jam, tapi payoff-nya huge untuk iterasi cepat dan deployment aman.
