// Rate limiting global (Upstash Redis) com fallback em memória por instância.
// Ativa o Redis quando UPSTASH_REDIS_REST_URL/TOKEN (ou KV_*) existem.
// Chaves com prefixo "linkium:rl:" p/ conviver com outros SaaS no mesmo Redis.
import { Redis } from "@upstash/redis"

const PREFIX = "linkium:rl:"
const _url = process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL
const _token = process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN
let redis: Redis | null = null
if (_url && _token) {
  try { redis = new Redis({ url: _url, token: _token }) } catch { redis = null }
}

// fallback em memória (best-effort por instância serverless)
const hits = new Map<string, { count: number; start: number }>()
function memRl(key: string, max: number, windowMs: number) {
  const now = Date.now()
  const e = hits.get(key)
  if (!e || now - e.start > windowMs) { hits.set(key, { count: 1, start: now }); return { ok: true, remaining: max - 1, retryAfter: 0 } }
  if (e.count >= max) return { ok: false, remaining: 0, retryAfter: Math.ceil((windowMs - (now - e.start)) / 1000) }
  e.count++
  return { ok: true, remaining: max - e.count, retryAfter: 0 }
}

export async function rateLimit(
  key: string,
  max: number,
  windowMs: number,
): Promise<{ ok: boolean; remaining: number; retryAfter: number }> {
  const windowSec = Math.max(1, Math.ceil(windowMs / 1000))
  if (redis) {
    try {
      const k = PREFIX + key
      const count = await redis.incr(k)
      if (count === 1) await redis.expire(k, windowSec)
      const ok = count <= max
      return { ok, remaining: Math.max(0, max - count), retryAfter: ok ? 0 : windowSec }
    } catch {
      /* falha no Redis → cai pro fallback */
    }
  }
  return memRl(key, max, windowMs)
}

export function clientIp(req: Request): string {
  const fwd = req.headers.get("x-forwarded-for") || ""
  return fwd.split(",")[0].trim() || req.headers.get("x-real-ip") || "unknown"
}

// limpeza periódica leve (só relevante no fallback em memória)
if (typeof globalThis !== "undefined") {
  const g = globalThis as unknown as { __rlTimer?: boolean }
  if (!g.__rlTimer) {
    g.__rlTimer = true
    setInterval(() => { const now = Date.now(); for (const [k, v] of hits) if (now - v.start > 3600000) hits.delete(k) }, 600000).unref?.()
  }
}
