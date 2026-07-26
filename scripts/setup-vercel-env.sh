#!/bin/bash
# Seta as env vars de Turnstile + Upstash num projeto Vercel (production).
# Secret Key e Redis token ficam SÓ no servidor. Rode ANTES do deploy.
# Uso: setup-vercel-env.sh <vercel_token> <projeto> <redis_url> <redis_token> <turnstile_site_key> <turnstile_secret_key> [scope]
set -euo pipefail
VTOK="${1:?vercel token}"; PROJ="${2:?projeto Vercel}"
RURL="${3:?upstash rest url}"; RTOK="${4:?upstash rest token}"
TSITE="${5:?turnstile site key}"; TSECRET="${6:?turnstile secret key}"
SCOPE="${7:-}"
SC=(); [ -n "$SCOPE" ] && SC=(--scope "$SCOPE")

# linka o projeto no diretório atual
vercel link --yes --project "$PROJ" "${SC[@]}" --token "$VTOK" >/dev/null 2>&1

setenv() {
  vercel env rm "$1" production --yes "${SC[@]}" --token "$VTOK" >/dev/null 2>&1 || true
  printf '%s' "$2" | vercel env add "$1" production "${SC[@]}" --token "$VTOK" >/dev/null 2>&1
  echo "  set $1"
}
setenv UPSTASH_REDIS_REST_URL   "$RURL"
setenv UPSTASH_REDIS_REST_TOKEN "$RTOK"
setenv NEXT_PUBLIC_TURNSTILE_SITE_KEY "$TSITE"   # pública (vai no bundle)
setenv TURNSTILE_SECRET_KEY     "$TSECRET"       # secreta (server-only)
echo "✅ Env vars setadas em production. Agora: limpar ._* recursivo + vercel --prod + alias."
