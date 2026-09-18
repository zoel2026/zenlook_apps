# Panduan Map Tiles untuk Production

## Status Saat Ini

App menggunakan **OpenStreetMap public tiles** (`tile.openstreetmap.org`):

```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.zenlook',
)
```

## ⚠️ PENTING: OSM Tile Usage Policy

OSM public tiles **TIDAK GRATIS** untuk aplikasi komersial atau dengan traffic tinggi.

**Batasan OSM Public Tiles:**
- Hanya untuk development/testing ringan
- Tidak boleh untuk aplikasi production dengan banyak user
- Rate limit ketat & bisa di-ban sewaktu-waktu
- Referensi: https://operations.osmfoundation.org/policies/tiles/

## Alternatif Tile Server untuk Production

### 1. **Mapbox** (Rekomendasi untuk produksi)

**Pros:**
- Free tier: 50,000 map loads/bulan
- Tile kualitas tinggi & cepat
- Custom styling tersedia
- SDK lengkap untuk Flutter

**Setup:**
```dart
// pubspec.yaml
dependencies:
  mapbox_maps_flutter: ^1.0.0

// Ganti TileLayer dengan:
TileLayer(
  urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token={accessToken}',
  additionalOptions: {
    'accessToken': 'YOUR_MAPBOX_TOKEN',
    'id': 'mapbox.streets',
  },
)
```

**Harga:**
- Free: 50k loads/bulan
- Pay as you go: $0.50 per 1,000 loads setelah free tier
- Link: https://www.mapbox.com/pricing

---

### 2. **Maptiler** (Alternatif murah)

**Pros:**
- Free tier: 100,000 tile requests/bulan
- OpenStreetMap-based
- Mudah migrasi dari OSM

**Setup:**
```dart
TileLayer(
  urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key={key}',
  additionalOptions: {
    'key': 'YOUR_MAPTILER_KEY',
  },
)
```

**Harga:**
- Free: 100k requests/bulan
- Basic: $39/bulan (3M requests)
- Link: https://www.maptiler.com/cloud/pricing/

---

### 3. **Stadia Maps**

**Pros:**
- Free tier: 200,000 tile requests/bulan
- OSM-based dengan CDN global
- Tidak perlu credit card untuk free tier

**Setup:**
```dart
TileLayer(
  urlTemplate: 'https://tiles.stadiamaps.com/tiles/osm_bright/{z}/{x}/{y}{r}.png?api_key={api_key}',
  additionalOptions: {
    'api_key': 'YOUR_STADIA_KEY',
  },
)
```

**Harga:**
- Free: 200k requests/bulan
- Pro: $49/bulan (1M requests)
- Link: https://stadiamaps.com/pricing/

---

### 4. **Self-Hosted Tile Server** (Advanced)

Untuk kontrol penuh dan biaya rendah jangka panjang.

**Stack:**
- Tile server: `tile-server-gl` atau `tileserver-php`
- Data: OpenStreetMap extracts
- Hosting: VPS (DigitalOcean, AWS, dll)

**Estimasi Biaya:**
- VPS (4GB RAM): ~$20/bulan
- Storage OSM data: 50-100GB untuk Indonesia
- Setup kompleks tapi biaya bulanan rendah

**Referensi:**
- https://github.com/maptiler/tileserver-gl
- https://switch2osm.org/serving-tiles/

---

## Rekomendasi Implementasi

### Development/Testing
Tetap gunakan OSM public tiles (saat ini).

### Production (Pilih salah satu):

**Untuk MVP/Startup (Budget rendah):**
→ **Stadia Maps** (200k free requests) atau **Maptiler** (100k free)

**Untuk Produksi Serius (Skalabilitas):**
→ **Mapbox** (ekosistem terbaik, custom styling)

**Untuk Long-term Cost Saving:**
→ **Self-hosted** (investasi setup tinggi, biaya bulanan rendah)

---

## Implementasi di Zenlook

### Step 1: Pilih Provider

Daftar akun di provider pilihan (contoh: Mapbox).

### Step 2: Simpan API Key di .env

```env
# .env
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
MAP_TILE_URL=https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token={accessToken}
MAPBOX_ACCESS_TOKEN=pk.xxxxx
```

### Step 3: Update map_tab.dart

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Di build method:
TileLayer(
  urlTemplate: dotenv.env['MAP_TILE_URL']!,
  additionalOptions: {
    'accessToken': dotenv.env['MAPBOX_ACCESS_TOKEN']!,
  },
  userAgentPackageName: 'com.zenlook.app',
)
```

### Step 4: Update .env.example

```env
MAP_TILE_URL=https://api.mapbox.com/styles/v1/mapbox/streets-v11/tiles/{z}/{x}/{y}?access_token={accessToken}
MAPBOX_ACCESS_TOKEN=your_mapbox_token_here
```

---

## Monitoring Usage

Setiap provider menyediakan dashboard untuk monitor tile requests:

- Mapbox: https://account.mapbox.com/
- Maptiler: https://cloud.maptiler.com/account/
- Stadia: https://client.stadiamaps.com/dashboard/

**Estimasi Usage:**
- 1 user aktif = ~500-1000 tile requests/hari (tergantung zoom & panning)
- 100 daily active users = ~50k-100k requests/hari
- Free tier Stadia (200k/bulan) ≈ 20-40 DAU

---

## Migration Checklist

- [ ] Pilih tile provider berdasarkan budget & estimasi traffic
- [ ] Daftar akun & dapatkan API key
- [ ] Tambahkan API key ke .env (JANGAN commit ke repo)
- [ ] Update map_tab.dart untuk baca dari .env
- [ ] Test di development
- [ ] Deploy ke production
- [ ] Setup monitoring & alerts untuk usage limit

---

**Catatan:**
Jika tetap menggunakan OSM public tiles untuk production, app bisa di-ban tanpa notice. Migrasi ke tile provider berbayar adalah **WAJIB** sebelum launch production dengan user base signifikan.

**Rekomendasi Edy:** Mulai dengan **Stadia Maps** (200k free) untuk MVP, migrate ke **Mapbox** saat DAU > 50.
