// Validação do Cloudflare Turnstile (anti-bot) no servidor.
// A Secret Key vive só em env var (TURNSTILE_SECRET_KEY), nunca no bundle.
// Estratégia: se não configurado → não bloqueia (para não travar antes das chaves).
// Se configurado: token ausente/ inválido → bloqueia. Erro de rede na verificação
// → não bloqueia (fail-open, para não derrubar login legítimo numa queda do CF).

export async function verifyTurnstile(token: string, ip?: string | null): Promise<boolean> {
  const secret = process.env.TURNSTILE_SECRET_KEY;
  if (!secret) return true; // ainda não configurado
  if (!token) return false; // configurado mas sem token → provável bot
  try {
    const body = new URLSearchParams({ secret, response: token });
    if (ip) body.set("remoteip", ip);
    const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
      signal: AbortSignal.timeout(4000),
    });
    const d = (await r.json()) as { success?: boolean };
    return Boolean(d.success);
  } catch {
    return true; // falha de rede na verificação → não trava o usuário
  }
}
