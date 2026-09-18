# Production Deployment Checklist — Zenlook Apps

**Last Updated:** 2026-09-18

Checklist lengkap sebelum deploy Zenlook Apps ke production.

---

## 📋 Pre-Launch Checklist

### 1. Code Quality

- [ ] **Flutter Analyze** bersih (0 issues)
  ```bash
  cd app && flutter analyze
  ```

- [ ] **All Tests Pass** (24/24 tests)
  ```bash
  cd app && flutter test
  ```

- [ ] **No TODO/FIXME** di kode production-critical

- [ ] **Code Review** completed (minimal 1 reviewer)

- [ ] **No Hardcoded Secrets** (API keys, passwords, tokens)
  ```bash
  grep -r "pk\." app/lib/  # Check Mapbox keys
  grep -r "sk\." app/lib/  # Check secret keys
  ```

---

### 2. Environment Configuration

- [ ] **`.env` tidak di-commit** (ada di `.gitignore`)

- [ ] **`.env.example` up-to-date** dengan semua keys

- [ ] **Production `.env` configured:**
  ```env
  SUPABASE_URL=https://ytmkhmsndfwmjlfyxiiw.supabase.co
  SUPABASE_ANON_KEY=eyJ... (anon key, bukan service_role!)
  MAP_TILE_URL=https://... (bukan OSM public tiles)
  MAPBOX_ACCESS_TOKEN=pk...
  ```

- [ ] **Verify environment loading:**
  ```dart
  print(dotenv.env['SUPABASE_URL']); // Should NOT be null
  ```

---

### 3. Database (Supabase)

- [ ] **Schema applied** via `schema.sql` di Supabase SQL Editor

- [ ] **RLS policies tested:**
  - User hanya bisa update profile sendiri
  - Location hanya visible ke accepted friends
  - Messages hanya visible ke sender/receiver
  - Private profiles owner-only

- [ ] **Rate limiting tested:**
  ```sql
  -- Test verify_security_code rate limit (5x/15min)
  SELECT verify_security_code('testuser', '123456');
  ```

- [ ] **Triggers verified:**
  - `handle_new_user` (auto-create profile)
  - `notify_new_message` (push notification)
  - `notify_nearby_users` (nearby alerts)
  - `track_location_history` (auto-log location)

- [ ] **Indexes created** (lihat schema.sql line 1278-1297)

- [ ] **Realtime subscriptions enabled:**
  ```sql
  -- Check publication
  SELECT * FROM pg_publication_tables WHERE pubname = 'supabase_realtime';
  ```

- [ ] **App secrets configured:**
  ```sql
  -- Set push_internal_key (JANGAN commit value ini!)
  INSERT INTO app_secrets (name, value)
  VALUES ('push_internal_key', 'RANDOM_SECRET_HERE')
  ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value;
  ```

---

### 4. Storage Buckets

- [ ] **`voice-messages` bucket:**
  - Public: ✅
  - Max size: 5 MB
  - MIME types: audio/mpeg, audio/mp4, audio/aac, audio/x-m4a, audio/wav
  - Upload policy: authenticated users only
  - Path pattern: `uploads/<uid>_<timestamp>.m4a`

- [ ] **`audio-files` bucket:**
  - Public: ✅
  - Max size: 25 MB
  - MIME types: audio/mpeg, audio/mp4, audio/aac, audio/x-m4a, audio/wav, audio/ogg
  - Upload policy: authenticated users only

- [ ] **Test upload & download:**
  ```dart
  // Upload test
  final path = await voiceService.upload(file, senderId: userId);
  // Download test
  final url = VoiceService.publicUrl(path);
  ```

---

### 5. Edge Functions

- [ ] **`send-push` deployed:**
  ```bash
  cd backend
  supabase functions deploy send-push --project-ref ytmkhmsndfwmjlfyxiiw
  ```

- [ ] **Environment variables set** di Supabase Dashboard:
  ```
  PUSH_INTERNAL_KEY=<sama dengan app_secrets.push_internal_key>
  FCM_SERVER_KEY=<Firebase server key>
  ```

- [ ] **Test push notification end-to-end:**
  - Send message via app
  - Verify FCM token tersimpan di `private_profiles.device_token`
  - Verify notification diterima di device

- [ ] **Check function logs** di Supabase Dashboard (no errors)

---

### 6. Firebase (FCM)

- [ ] **`google-services.json` configured:**
  - Downloaded dari Firebase Console
  - Placed di `app/android/app/`
  - **TIDAK** di-commit ke git (ada di `.gitignore`)

- [ ] **FCM initialized** di `main.dart`:
  ```dart
  await PushService.init();
  await FcmService.init();
  ```

- [ ] **Notification permissions requested:**
  ```dart
  final perm = await messaging.requestPermission();
  // Should return authorized
  ```

- [ ] **Test push notification:**
  - Send test message dari Firebase Console
  - Send message via app (trigger edge function)
  - Verify notification tampil di foreground & background

- [ ] **Notification channels configured** (Android):
  - Default channel: `zenlook_notifications`
  - Audio channel: `com.example.zenlook.channel.audio`

---

### 7. Map Tiles

- [ ] **OSM public tiles TIDAK digunakan** ⚠️

- [ ] **Production tile provider dipilih:**
  - [ ] Mapbox (50k free/mo)
  - [ ] Maptiler (100k free/mo)
  - [ ] Stadia Maps (200k free/mo) ← Recommended untuk MVP
  - [ ] Self-hosted

- [ ] **API key configured** di `.env`:
  ```env
  MAP_TILE_URL=https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png?api_key={api_key}
  STADIA_API_KEY=your_key_here
  ```

- [ ] **Update `map_tab.dart`:**
  ```dart
  TileLayer(
    urlTemplate: dotenv.env['MAP_TILE_URL']!,
    additionalOptions: {'api_key': dotenv.env['STADIA_API_KEY']!},
    userAgentPackageName: 'com.zenlook.app',
  )
  ```

- [ ] **Usage monitoring setup** di tile provider dashboard

- [ ] **Test map loading:**
  - Zoom in/out
  - Pan around
  - Check tile requests di network tab

---

### 8. Location Services

- [ ] **Permissions configured** di `AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
  ```

- [ ] **Always-share location tested:**
  - Toggle "Bagikan lokasi selalu" di profil
  - Verify location updates saat app di background
  - Check battery impact (should be reasonable)

- [ ] **Battery saver mode tested:**
  - Toggle "Mode Hemat Baterai"
  - Verify polling interval lebih jarang saat idle
  - Check battery stats

- [ ] **Nearby alerts tested:**
  - Enable di profil (set radius 500m)
  - Simulate user masuk radius
  - Verify push notification diterima

---

### 9. Security

- [ ] **Security codes stored as bcrypt hash** (NOT plaintext)
  ```sql
  SELECT security_code FROM private_profiles LIMIT 1;
  -- Should return bcrypt hash: $2b$12$...
  ```

- [ ] **Rate limiting active:**
  - `verify_security_code`: 5x/15min
  - `reset_password_with_code`: 3x/15min
  - `user_reports`: 1x/24h per target

- [ ] **Service role key TIDAK exposed** di client
  ```bash
  grep -r "service_role" app/lib/  # Should return nothing
  ```

- [ ] **Input validation di client & server:**
  - Username: 3-24 chars, alphanumeric + underscore
  - Password: min 6 chars
  - Security code: exactly 6 digits
  - Email: valid format

- [ ] **HTTPS everywhere** (Supabase, tile server, storage)

- [ ] **No SQL injection** (pakai parameterized queries)

---

### 10. Performance

- [ ] **App size < 50 MB** (APK)
  ```bash
  flutter build apk --release
  ls -lh app/build/app/outputs/flutter-apk/app-release.apk
  ```

- [ ] **Cold start < 3s** di mid-range device

- [ ] **Location updates efficient:**
  - Foreground: 5s interval (battery saver: 15s)
  - Background: 30s interval (battery saver: 60s)

- [ ] **Database queries optimized:**
  - No N+1 queries
  - Indexes pada foreign keys
  - LIMIT di queries yang return list

- [ ] **Image caching enabled:**
  ```dart
  CachedNetworkImage(imageUrl: avatarUrl)
  ```

- [ ] **Realtime subscriptions cleanup:**
  ```dart
  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }
  ```

---

### 11. User Experience

- [ ] **Loading states** di semua async operations

- [ ] **Error messages** user-friendly (Indonesian & English)

- [ ] **Offline handling:**
  - "Tidak ada koneksi internet" message
  - Retry button
  - Queue messages untuk dikirim saat online (optional)

- [ ] **Empty states:**
  - No friends: "Belum ada teman. Cari dan tambah teman di atas."
  - No messages: "Belum ada percakapan"
  - No music: "Belum ada lagu. Ketuk + untuk pilih MP3."

- [ ] **Confirmation dialogs** untuk destructive actions:
  - Hapus teman
  - Blokir user
  - Logout

- [ ] **Dark mode** tested & consistent

- [ ] **Localization** (ID/EN) lengkap di semua screen

---

### 12. Build & Versioning

- [ ] **Version bump** di `pubspec.yaml`:
  ```yaml
  version: 1.0.0+1  # Format: major.minor.patch+build
  ```

- [ ] **Update `CHANGELOG.md`:**
  ```markdown
  ## [1.0.0] - 2026-09-18
  ### Added
  - Real-time location sharing
  - Friend requests
  - 1-on-1 chat with voice messages
  - Push notifications
  ```

- [ ] **Build release APK:**
  ```bash
  cd app
  flutter clean
  flutter pub get
  flutter build apk --release
  ```

- [ ] **Build App Bundle** (untuk Play Store):
  ```bash
  flutter build appbundle --release
  ```

- [ ] **Test release build** di real device (NOT emulator)

- [ ] **Verify no debug symbols** di release build

---

### 13. Legal & Compliance

- [ ] **Privacy Policy** (required untuk Play Store):
  - Data yang dikumpulkan (lokasi, chat, profil)
  - Bagaimana data disimpan & digunakan
  - User rights (delete account, export data)

- [ ] **Terms of Service**

- [ ] **GDPR compliance** (jika target EU users):
  - Consent untuk location tracking
  - Right to be forgotten (delete account)
  - Data export

- [ ] **App Store listing:**
  - Description
  - Screenshots (5-8 images)
  - Feature graphic
  - Privacy policy link
  - Support email

---

### 14. Monitoring & Analytics

- [ ] **Crashlytics setup** (Firebase):
  ```dart
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  ```

- [ ] **Sentry setup** (optional, alternative to Crashlytics):
  ```dart
  await SentryFlutter.init((options) {
    options.dsn = 'YOUR_SENTRY_DSN';
  });
  ```

- [ ] **Analytics events tracked:**
  - User signup
  - Friend request sent/accepted
  - Message sent
  - Location updated
  - Nearby alert triggered

- [ ] **Error tracking tested:**
  - Throw test error
  - Verify tampil di Crashlytics/Sentry dashboard

---

### 15. Backup & Disaster Recovery

- [ ] **Database backup enabled** di Supabase (auto daily)

- [ ] **Backup edge function code** (committed to git)

- [ ] **Backup environment variables** (secure location, NOT git)

- [ ] **Rollback plan documented** (lihat CI_CD_SETUP.md)

- [ ] **Test restore dari backup:**
  - Create test project
  - Restore schema.sql
  - Verify RLS & triggers

---

## 🚀 Launch Day

### Morning (Pre-Launch)

- [ ] **Final smoke test:**
  - Register new account
  - Add friend
  - Send message
  - Share location
  - Receive push notification

- [ ] **Monitor Supabase dashboard:**
  - Database CPU/memory
  - Realtime connections
  - Edge function invocations

- [ ] **Check tile server status** (uptime)

- [ ] **Verify Firebase quota** (FCM unlimited, tapi cek dashboard)

### Launch

- [ ] **Upload APK/AAB** ke Google Play Console

- [ ] **Set production track** (atau internal/beta testing dulu)

- [ ] **Submit for review** (Play Store review: 1-3 hari)

### Post-Launch (First 24h)

- [ ] **Monitor crashes** di Crashlytics (target: < 1% crash rate)

- [ ] **Monitor errors** di Supabase logs

- [ ] **Monitor tile usage** (jangan exceed free tier)

- [ ] **Check user feedback** (reviews, support email)

- [ ] **Watch server metrics:**
  - Database response time
  - Realtime concurrent connections
  - Edge function errors

- [ ] **Be ready for hotfix** (jika ada critical bug)

---

## 📊 Success Metrics (Week 1)

- [ ] **Crash-free rate > 99%**
- [ ] **Average session > 5 min**
- [ ] **Retention D1 > 40%**
- [ ] **Push notification delivery > 95%**
- [ ] **Location update success > 98%**
- [ ] **No tile server ban** (respect usage limits)

---

## 🆘 Emergency Contacts

**Backend Issues (Supabase):**
- Dashboard: https://app.supabase.com/project/ytmkhmsndfwmjlfyxiiw
- Support: support@supabase.com

**App Crashes:**
- Crashlytics: https://console.firebase.google.com
- Rollback: Deploy previous APK version

**Tile Server Down:**
- Fallback to OSM temporary (edit map_tab.dart, hotfix deploy)

**Database Down:**
- Check Supabase status: https://status.supabase.com
- Enable maintenance mode di app (show banner)

---

## ✅ Final Sign-Off

**Reviewed by:**
- [ ] Developer (Edy): __________________
- [ ] QA Tester: __________________
- [ ] Product Owner: __________________

**Approval Date:** _____________

**Launch Date:** _____________

---

**Catatan:**
Checklist ini komprehensif untuk production launch. Untuk MVP/beta testing, prioritas minimal:
- Code quality (analyze + test)
- Database RLS
- Push notifications working
- Map tiles NOT using OSM public
- No hardcoded secrets

Good luck Bos! 🚀
