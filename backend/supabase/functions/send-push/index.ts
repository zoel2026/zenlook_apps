// ============================================================================
// send-push — Supabase Edge Function (Deno)
// Kirim push notification via FCM HTTP v1 API.
//
// NOTE: Legacy API (fcm.googleapis.com/fcm/send + server key) sudah
// dimatikan Google sejak Juni 2024 dan TIDAK bisa dipakai lagi.
//
// Env yang dibutuhkan:
//   SUPABASE_URL              -> otomatis tersedia di Supabase
//   SUPABASE_SERVICE_ROLE_KEY -> otomatis tersedia di Supabase
//   FIREBASE_SERVICE_ACCOUNT  -> isi JSON service account Firebase
//                                (boleh mentah atau base64).
//                                Firebase Console > Project settings >
//                                Service accounts > Generate new private key
//   PUSH_INTERNAL_KEY         -> shared secret; HARUS sama dengan baris
//                                'push_internal_key' di tabel app_secrets.
//                                Request tanpa x-internal-key yang cocok
//                                ditolak (anti spam dari pihak luar).
//
// Body:
//   { "userId": "<uuid>", "title": "Pesan baru", "body": "Budi: halo",
//     "senderId": "<uuid opsional — diteruskan ke app untuk suppress notif>" }
//
// Tipe 'nearby' (Nearby Alert — user terdekat):
//   { "type": "nearby", "userId", "title", "body",
//     "name", "distance_m", "latitude", "longitude" }
//   Field ekstra (type/name/distance_m/latitude/longitude) diteruskan apa
//   adanya ke data payload; app membedakan lewat data['type'].
//
// Tipe 'wave' (Wave / ping ke teman):
//   { "type": "wave", "userId", "title", "body", "senderId" }
//   Sama seperti chat: data-only, app menampilkan notifikasi lokal. Tidak ada
//   penanganan khusus selain meneruskan data['type'] & data['sender_id'].
//
// Pesan dikirim sebagai DATA-ONLY (tanpa blok notification) supaya
// aplikasi punya kendali penuh: bisa menekan notifikasi saat chat
// dengan pengirim sedang terbuka. Aplikasi yang menampilkan notifikasinya.
// ============================================================================

import { createClient } from 'npm:@supabase/supabase-js@2'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const supabaseServiceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

let serviceAccount: {
  project_id: string
  client_email: string
  private_key: string
}
try {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? ''
  serviceAccount = JSON.parse(raw.trim().startsWith('{') ? raw : atob(raw))
} catch (_) {
  console.error('FIREBASE_SERVICE_ACCOUNT missing or invalid')
  serviceAccount = { project_id: '', client_email: '', private_key: '' }
}

const supabase = createClient(supabaseUrl, supabaseServiceRole)

// ---------------------------------------------------------------------------
// OAuth2 — tukar JWT (RS256) service account menjadi access token FCM v1
// ---------------------------------------------------------------------------
let cachedToken: { token: string; expiresAt: number } | null = null

function base64Url(input: string | ArrayBuffer): string {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input)
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '')
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.token

  const header = { alg: 'RS256', typ: 'JWT' }
  const claim = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }
  const unsigned =
    `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(claim))}`

  const pkcs8 = serviceAccount.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '')
  const keyBytes = Uint8Array.from(atob(pkcs8), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyBytes,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  )
  const jwt = `${unsigned}.${base64Url(signature)}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  if (!res.ok) throw new Error(`OAuth token exchange failed: ${res.status}`)
  const json = await res.json()
  cachedToken = { token: json.access_token, expiresAt: now + (json.expires_in ?? 3600) }
  return cachedToken.token
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------
function jsonResponse(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  try {
    // Anti-spam: hanya request dari trigger DB (yang membawa shared secret)
    // yang dilayani. Tanpa ini, siapa pun dengan anon key bisa mengirim
    // push notif ke user mana pun.
    const internalKey = Deno.env.get('PUSH_INTERNAL_KEY') ?? ''
    if (
      !internalKey ||
      req.headers.get('x-internal-key') !== internalKey
    ) {
      return jsonResponse({ ok: false, error: 'unauthorized' }, 401)
    }

    const { userId, title, body, senderId, type, name, distance_m, latitude, longitude } =
      await req.json()
    if (!userId || !title || !body) {
      return jsonResponse(
        { ok: false, error: 'userId, title, and body are required' },
        400,
      )
    }

    const { data, error } = await supabase
      .from('private_profiles')
      .select('device_token')
      .eq('id', userId)
      .maybeSingle()

    if (error) return jsonResponse({ ok: false, error: error.message }, 500)
    if (!data?.device_token) {
      return jsonResponse({ ok: false, error: 'no device token' }, 404)
    }

    const accessToken = await getAccessToken()
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: data.device_token,
            // Data-only: nilai harus string semua.
            data: {
              title: String(title),
              body: String(body),
              ...(senderId ? { sender_id: String(senderId) } : {}),
              ...(type ? { type: String(type) } : {}),
              ...(name ? { name: String(name) } : {}),
              ...(distance_m != null ? { distance_m: String(distance_m) } : {}),
              ...(latitude != null ? { latitude: String(latitude) } : {}),
              ...(longitude != null ? { longitude: String(longitude) } : {}),
            },
          },
        }),
      },
    )
    if (!fcmRes.ok) {
      console.error('FCM error:', await fcmRes.text())
    }

    return jsonResponse({ ok: fcmRes.ok }, fcmRes.ok ? 200 : 502)
  } catch (e) {
    console.error('send-push error:', e)
    return jsonResponse({ ok: false, error: 'internal error' }, 500)
  }
})
