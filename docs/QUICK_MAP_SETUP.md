# Quick Setup: Map Tiles Production-Ready

## 🚨 URGENT: Ganti OSM Public Tiles Sebelum Production

Project Zenlook **sudah siap** untuk production tile server. Tinggal pilih provider dan setup API key.

---

## ⚡ Setup Cepat (15 menit)

### Pilihan 1: Stadia Maps (RECOMMENDED untuk MVP)

**Free Tier:** 200,000 requests/bulan (cukup untuk 20-40 DAU)

#### Step 1: Daftar Akun
1. Buka https://client.stadiamaps.com/signup/
2. Pilih "Free" plan
3. Verifikasi email

#### Step 2: Dapatkan API Key
1. Login ke https://client.stadiamaps.com/dashboard/
2. Klik "Create API Key"
3. Name: `Zenlook Production`
4. Copy API key yang dihasilkan

#### Step 3: Update .env
```bash
cd D:\mobile_apps\zenlook_apps\app
```

Edit `.env`, tambahkan:
```env
MAP_TILE_URL=https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png
STADIA_API_KEY=paste_your_api_key_here
```

#### Step 4: Test
```bash
flutter run
```

Buka tab Map, zoom in/out, pastikan tiles loading dengan baik.

#### Step 5: Monitor Usage
Dashboard: https://client.stadiamaps.com/dashboard/
- Check daily requests
- Setup alert saat mendekati limit (180k/bulan)

---

### Pilihan 2: Mapbox (Lebih Advanced)

**Free Tier:** 50,000 map loads/bulan

#### Step 1: Daftar
https://account.mapbox.com/auth/signup/

#### Step 2: Dapatkan Token
1. Dashboard → https://account.mapbox.com/access-tokens/
2. Create token → Name: `Zenlook Production`
3. Scopes: pilih `styles:tiles`, `styles:read`
4. Copy "Public token"

#### Step 3: Update .env
```env
MAP_TILE_URL=https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}
MAPBOX_ACCESS_TOKEN=pk.your_public_token_here
```

#### Step 4: Custom Styles (Optional)
Mapbox Studio: https://studio.mapbox.com/
- Buat custom style sesuai brand Zenlook
- Replace `streets-v11` dengan style ID kamu

---

### Pilihan 3: Maptiler

**Free Tier:** 100,000 requests/bulan

#### Step 1: Daftar
https://cloud.maptiler.com/auth/widget

#### Step 2: API Key
Dashboard → API keys → Copy key

#### Step 3: Update .env
```env
MAP_TILE_URL=https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png
MAPTILER_API_KEY=your_key_here
```

---

## 🧪 Testing Checklist

Setelah setup, test:

- [ ] Map loading di app (tidak ada error tile)
- [ ] Zoom in sampai level 18
- [ ] Zoom out sampai level 5
- [ ] Pan ke berbagai lokasi (Indonesia, luar negeri)
- [ ] Check browser DevTools network tab (status 200, bukan 429)
- [ ] Tile requests ada di dashboard provider (confirm API key working)

---

## 📊 Estimasi Usage

**Rumus:** 1 user aktif ≈ 500-1000 tile requests/hari

| DAU | Requests/Bulan | Provider Recommended |
|-----|----------------|---------------------|
| 10  | 20k            | Semua free tier OK  |
| 50  | 100k           | Stadia/Maptiler     |
| 100 | 200k           | Stadia (max free)   |
| 200 | 400k           | Mapbox Pro ($49/mo) |
| 500 | 1M             | Mapbox Pro          |

---

## 🚨 Fallback Strategy

Jika tile server down atau limit tercapai:

### Emergency Fallback (sementara):

Edit `map_tab.dart` line 606:
```dart
String _getTileUrl() {
  final url = dotenv.env['MAP_TILE_URL'];
  if (url != null && url.isNotEmpty) {
    return url;
  }
  // Emergency fallback (ONLY for temporary downtime)
  return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}
```

**Warning:** Jangan gunakan OSM sebagai fallback permanent. Bisa di-ban.

### Production Fallback (recommended):

Backup dengan provider kedua:
```dart
String _getTileUrl() {
  final primary = dotenv.env['MAP_TILE_URL'];
  final fallback = dotenv.env['MAP_TILE_URL_FALLBACK'];
  
  // Try primary first, fallback if empty
  if (primary != null && primary.isNotEmpty) return primary;
  if (fallback != null && fallback.isNotEmpty) return fallback;
  
  // Last resort (maintenance mode)
  return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
}
```

---

## 💰 Biaya Production (Estimasi)

### Scenario: 100 DAU

**Stadia Maps (Free):**
- 200k requests/bulan = GRATIS ✅
- Cukup sampai 100 DAU

**Jika Exceed Free Tier:**
- Upgrade ke Stadia Pro: $49/bulan (1M requests)
- Atau Mapbox Pay-as-you-go: $0.50/1000 requests

### Scenario: 1000 DAU

**Mapbox:**
- ~5M requests/bulan
- Cost: ~$250/bulan
- Termasuk custom styling & SDK lengkap

**Self-hosted:**
- VPS $50/bulan + maintenance time
- One-time setup: 8-16 jam
- Break-even: >500 DAU

---

## 📝 Deployment Checklist

Sebelum push ke production:

- [ ] `.env` punya tile URL & API key
- [ ] `.env.example` updated (template tanpa key)
- [ ] `.gitignore` contains `.env` (jangan commit API key!)
- [ ] Test di real device (bukan emulator)
- [ ] Check tile request di provider dashboard
- [ ] Setup usage alert (80% dari limit)
- [ ] Dokumentasi API key di password manager tim
- [ ] Backup API key di secure location (1Password/Bitwarden)

---

## 🆘 Troubleshooting

### Tiles tidak loading (blank map)

**Check:**
1. `.env` file ada di `app/` directory
2. API key correct (tidak ada typo)
3. `flutter clean && flutter pub get && flutter run`
4. Check console log untuk error messages

**Test manual:**
```bash
# Test Stadia URL
curl "https://tiles.stadiamaps.com/tiles/osm_bright/14/13371/7605.png?api_key=YOUR_KEY"

# Should return image (200 OK), not 401/403
```

### Rate limit exceeded (HTTP 429)

**Short-term:**
1. Fallback ke OSM temporary
2. Reduce polling frequency
3. Implement tile caching

**Long-term:**
1. Upgrade plan di provider
2. Switch ke provider dengan limit lebih tinggi
3. Consider self-hosted

### API key leaked di Git

**Immediate actions:**
1. Revoke key di provider dashboard
2. Generate new key
3. Update `.env` dan redeploy
4. Audit git history: `git log -S "old_api_key"`
5. Rewrite git history jika commit public:
   ```bash
   git filter-branch --force --index-filter \
   'git rm --cached --ignore-unmatch .env' \
   --prune-empty --tag-name-filter cat -- --all
   ```

---

## ✅ Status Implementasi

- [x] Code sudah support production tiles
- [x] Fallback ke OSM jika env kosong (dev only)
- [x] Support 3 provider (Stadia, Mapbox, Maptiler)
- [x] `.env.example` template ready
- [ ] **TODO: Pilih provider & setup API key** ← **KAMU DI SINI**
- [ ] Test di production environment
- [ ] Monitor usage first week

---

## 🎯 Next Action (Pilih salah satu)

**For Development/Testing (sekarang):**
→ Tetap pakai OSM (sudah fallback otomatis jika MAP_TILE_URL kosong)

**For MVP Launch (sebelum deploy):**
→ Setup **Stadia Maps** (15 menit, 200k free)

**For Scale (>100 DAU):**
→ Migrate ke **Mapbox** atau self-hosted

---

**Rekomendasi Edy:**
1. **Sekarang:** Keep OSM untuk development (no action needed)
2. **1 hari sebelum launch:** Setup Stadia Maps (15 menit)
3. **Setelah 50+ DAU:** Monitor usage, siap upgrade/migrate

**File ini dibuat:** 2026-09-18 09:44 WIB
