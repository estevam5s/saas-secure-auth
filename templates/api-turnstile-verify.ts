import { NextResponse } from "next/server"
import { verifyTurnstile } from "@/lib/turnstile"
import { rateLimit, clientIp } from "@/lib/rate-limit"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

// Verifica o token do Turnstile antes do login (que é client-side). Também
// aplica rate-limit por IP p/ não deixar o próprio verify virar vetor de abuso.
export async function POST(req: Request) {
  const rl = await rateLimit(`turnstile:${clientIp(req)}`, 30, 60000)
  if (!rl.ok) return NextResponse.json({ ok: false, error: "Muitas tentativas." }, { status: 429 })
  let b: any = {}
  try { b = await req.json() } catch {}
  const ok = await verifyTurnstile(String(b.token || ""), clientIp(req))
  return NextResponse.json({ ok }, { status: ok ? 200 : 400 })
}
