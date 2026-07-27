#!/bin/bash
# 🟢 DESLIGA o botão de pânico — volta o site ao funcionamento NORMAL.
# Tira o "Under Attack Mode" e devolve o security_level para "medium".
# A tela de verificação volta a aparecer SÓ nas rotas sensíveis (/login, /auth,
# /api/auth, /api/chat) — o resto do site abre direto, como no dia a dia.
#
# Uso:
#   ./desliga-panico.sh <dominio>
#   ./desliga-panico.sh pytrack.com.br
#
# Token: em ~/.cf-token ou export CF_API_TOKEN (permissão Zona: Configurações de zona → Editar).
set -euo pipefail

DOMAIN="${1:?Informe o domínio. Ex: ./desliga-panico.sh pytrack.com.br}"
CFTOK="${CF_API_TOKEN:-$(cat "$HOME/.cf-token" 2>/dev/null || true)}"
[ -z "${CFTOK:-}" ] && { echo "✗ Token do Cloudflare não encontrado. Exporte CF_API_TOKEN ou salve em ~/.cf-token"; exit 1; }

API="https://api.cloudflare.com/client/v4"
H=(-H "Authorization: Bearer $CFTOK" -H "Content-Type: application/json")

ZONE=$(curl -sS -m 20 "$API/zones?name=$DOMAIN" "${H[@]}" | python3 -c 'import json,sys;r=json.load(sys.stdin).get("result") or [];print(r[0]["id"] if r else "")')
[ -z "$ZONE" ] && { echo "✗ Zona $DOMAIN não encontrada nessa conta Cloudflare."; exit 1; }

echo "🟢 Desligando o modo de ataque em $DOMAIN (voltando ao normal) ..."
RESP=$(curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/security_level" "${H[@]}" -d '{"value":"medium"}')
OK=$(echo "$RESP" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("success"))')
if [ "$OK" = "True" ]; then
  echo "✅ NORMALIZADO. Só o login/auth continua com verificação; o resto do site abre direto."
else
  echo "✗ Falhou: $RESP"
  exit 1
fi
