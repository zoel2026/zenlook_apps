# GitHub Actions Setup Guide — Zenlook Apps

## Overview

Project ini sudah include 3 GitHub Actions workflows untuk CI/CD automation:

1. **Flutter CI** - Auto test & analyze
2. **Android Release** - Build APK/AAB otomatis
3. **Supabase Deploy** - Auto deploy edge functions

---

## Workflows

### 1. Flutter CI (`flutter-ci.yml`)

**Trigger:**
- Push ke branch `main` atau `develop`
- Pull request ke `main` atau `develop`

**Jobs:**
- ✅ Format verification
- ✅ Flutter analyze
- ✅ Run all tests
- ✅ Upload coverage to Codecov (optional)

**Status:** Langsung aktif setelah push

---

### 2. Android Release (`android-release.yml`)

**Trigger:**
- Push tag dengan format `v*` (contoh: `v1.0.0`)
- Manual via workflow_dispatch

**Jobs:**
- ✅ Run tests
- ✅ Build APK (release)
- ✅ Build AAB (release)
- ✅ Upload artifacts
- ✅ Create GitHub release

**Output:**
- `zenlook-v{version}-release.apk`
- `zenlook-v{version}-release.aab`
- GitHub release dengan download links

---

### 3. Supabase Deploy (`supabase-deploy.yml`)

**Trigger:**
- Push ke `main` dengan changes di `backend/supabase/functions/**`
- Manual via workflow_dispatch

**Jobs:**
- ✅ Deploy `send-push` edge function
- ✅ Verify deployment

---

## Setup GitHub Secrets

Sebelum workflows bisa jalan, tambahkan secrets di GitHub repo:

**Settings > Secrets and variables > Actions > New repository secret**

### Required Secrets

```
SUPABASE_URL
Value: https://ytmkhmsndfwmjlfyxiiw.supabase.co

SUPABASE_ANON_KEY
Value: eyJhbGc... (anon key dari Supabase dashboard)

SUPABASE_ACCESS_TOKEN
Value: (dapatkan via: supabase login, lalu copy token)
```

### Optional Secrets (untuk production tiles)

```
MAP_TILE_URL
Value: https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png

STADIA_API_KEY
Value: (API key dari Stadia Maps dashboard)

CODECOV_TOKEN
Value: (untuk upload test coverage, optional)
```

---

## Cara Pakai

### Test CI Otomatis

```bash
# Push ke branch develop atau main
git add .
git commit -m "Test CI pipeline"
git push origin develop

# Check di GitHub > Actions tab
# Workflow "Flutter CI" akan jalan otomatis
```

### Build Release

```bash
# 1. Update version di pubspec.yaml
# version: 1.0.1+2

# 2. Commit changes
git add app/pubspec.yaml
git commit -m "Bump version to 1.0.1"

# 3. Create & push tag
git tag v1.0.1
git push origin v1.0.1

# 4. Check GitHub > Actions
# Workflow "Android Release" akan build APK & AAB

# 5. Download dari GitHub > Releases
```

### Deploy Edge Functions

```bash
# 1. Edit function di backend/supabase/functions/send-push/

# 2. Commit & push
git add backend/supabase/functions/
git commit -m "Update send-push function"
git push origin main

# 3. Auto-deploy ke Supabase
# Check di Supabase Dashboard > Edge Functions
```

---

## Manual Trigger

Semua workflows bisa di-trigger manual:

1. Buka GitHub repo
2. Go to **Actions** tab
3. Pilih workflow (Flutter CI / Android Release / Supabase Deploy)
4. Klik **Run workflow**
5. Pilih branch
6. Klik **Run workflow** hijau

---

## Troubleshooting

### CI Gagal: "Flutter analyze found issues"

**Fix:**
```bash
cd app
flutter analyze
# Fix issues yang muncul
git commit -am "Fix analyze issues"
git push
```

### Release Gagal: "Secrets not found"

**Check:**
1. GitHub > Settings > Secrets and variables > Actions
2. Pastikan semua required secrets sudah ditambahkan
3. Re-run workflow

### Supabase Deploy Gagal: "Authentication failed"

**Fix:**
```bash
# 1. Login ke Supabase CLI
supabase login

# 2. Copy access token yang muncul
# 3. Update SUPABASE_ACCESS_TOKEN secret di GitHub
```

### Build APK Gagal: "Environment variables missing"

**Temporary workaround:**

Edit `.github/workflows/android-release.yml`, hapus baris create .env file jika tidak butuh (untuk development testing):

```yaml
# Comment out atau hapus:
# - name: Create .env file
#   working-directory: ./app
#   run: |
#     echo "SUPABASE_URL=..." >> .env
```

---

## Monitoring

### Check CI Status

**Badge di README:**
```markdown
![Flutter CI](https://github.com/YOUR_USERNAME/zenlook_apps/actions/workflows/flutter-ci.yml/badge.svg)
```

**GitHub Actions Tab:**
- Green ✅ = All checks passed
- Red ❌ = Failed (klik untuk lihat logs)
- Yellow 🟡 = Running

### Release Artifacts

**Download builds:**
1. GitHub > Actions
2. Pilih workflow run "Android Release"
3. Scroll ke "Artifacts"
4. Download APK atau AAB

**Or:**
1. GitHub > Releases
2. Download dari latest release

---

## Best Practices

### Branch Protection

Setup branch protection untuk `main`:

**Settings > Branches > Add rule**
- Branch name pattern: `main`
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- Select: `Test & Analyze`

### Release Flow

```bash
# Development
git checkout -b feature/new-feature
# ... develop
git push origin feature/new-feature
# Create PR → CI auto-run

# After merge to main
git checkout main
git pull

# Bump version
# Edit app/pubspec.yaml: version: 1.0.1+2

git commit -am "Release v1.0.1"
git tag v1.0.1
git push origin main --tags

# Wait for GitHub Actions to build & release
```

---

## Cost

**GitHub Actions Free Tier:**
- 2000 minutes/month (public repos: unlimited)
- Storage: 500 MB

**Usage Estimate:**
- 1 CI run: ~5 minutes
- 1 Release build: ~15 minutes
- 100 commits/month = ~500 minutes ✅

**Private repo estimate:**
- 40 CI runs + 4 releases = ~200 minutes/month ✅ (masih dalam free tier)

---

## Next Steps

1. **Setup GitHub repo:**
   ```bash
   # Create repo di GitHub
   # Copy repo URL
   
   git remote add origin https://github.com/YOUR_USERNAME/zenlook_apps.git
   git branch -M main
   git push -u origin main
   ```

2. **Add secrets** (lihat section "Setup GitHub Secrets" di atas)

3. **Test CI:**
   ```bash
   git checkout -b test-ci
   echo "# Test" >> README.md
   git commit -am "Test CI pipeline"
   git push origin test-ci
   # Check GitHub Actions tab
   ```

4. **Setup branch protection** (optional tapi recommended)

---

## Status

- [x] Workflows created
- [x] Documentation ready
- [ ] GitHub repo setup
- [ ] Secrets configured
- [ ] First CI run tested
- [ ] First release built

---

**Created:** 2026-09-18  
**Workflows:** 3 (CI, Release, Supabase)  
**Ready:** Yes, tinggal push ke GitHub
