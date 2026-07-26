#!/bin/bash
# Configura SSL + Managed Challenge numa zona Cloudflare já adicionada (proxy).
# Pré: domínio adicionado ao Cloudflare + nameserver trocado no registrador.
# Uso: setup-cloudflare-proxy.sh <cf_api_token> <dominio>
set -euo pipefail
CFTOK="${1:?token de API do Cloudflare}"
DOMAIN="${2:?domínio, ex: meusaas.com}"
API="https://api.cloudflare.com/client/v4"
H=(-H "Authorization: Bearer $CFTOK" -H "Content-Type: application/json")

ZONE=$(curl -sS -m 20 "$API/zones?name=$DOMAIN" "${H[@]}" | python3 -c 'import json,sys;r=json.load(sys.stdin).get("result") or [];print(r[0]["id"] if r else "")')
[ -z "$ZONE" ] && { echo "✗ zona $DOMAIN não encontrada (adicione no Cloudflare primeiro)"; exit 1; }
STATUS=$(curl -sS -m 20 "$API/zones/$ZONE" "${H[@]}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["status"])')
echo "zona: $ZONE | status: $STATUS $([ "$STATUS" != active ] && echo '(config aplica quando propagar)')"

ok() { python3 -c 'import json,sys;d=json.load(sys.stdin);print("  ✅" if d.get("success") else "  ✗ "+str(d.get("errors")))'; }
echo "SSL strict:";        curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/ssl" "${H[@]}" -d '{"value":"strict"}' | ok
echo "Always HTTPS:";      curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/always_use_https" "${H[@]}" -d '{"value":"on"}' | ok
echo "min TLS 1.2:";       curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/min_tls_version" "${H[@]}" -d '{"value":"1.2"}' | ok
echo "Managed Challenge (login/auth/api):"
curl -sS -m 25 -X PUT "$API/zones/$ZONE/rulesets/phases/http_request_firewall_custom/entrypoint" "${H[@]}" -d '{
  "rules":[{"action":"managed_challenge",
    "expression":"(http.request.uri.path contains \"/login\") or (http.request.uri.path contains \"/auth\") or (starts_with(http.request.uri.path,\"/api/auth\")) or (starts_with(http.request.uri.path,\"/api/chat\"))",
    "description":"Managed Challenge em login/auth (anti-bot na borda)","enabled":true}]}' | ok
echo "→ Quando a zona ficar 'active', teste: $DOMAIN/login (tela CF) e a raiz (abre normal)."
