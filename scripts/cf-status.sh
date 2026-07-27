#!/bin/bash
# ℹ️  Mostra o estado atual da proteção Cloudflare de um domínio.
# Uso: ./status.sh <dominio>   (ex: ./status.sh pytrack.com.br)
set -euo pipefail
DOMAIN="${1:?Informe o domínio. Ex: ./status.sh pytrack.com.br}"
CFTOK="${CF_API_TOKEN:-$(cat "$HOME/.cf-token" 2>/dev/null || true)}"
[ -z "${CFTOK:-}" ] && { echo "✗ Token não encontrado (~/.cf-token ou CF_API_TOKEN)"; exit 1; }
API="https://api.cloudflare.com/client/v4"
H=(-H "Authorization: Bearer $CFTOK")
ZONE=$(curl -sS -m 20 "$API/zones?name=$DOMAIN" "${H[@]}" | python3 -c 'import json,sys;r=json.load(sys.stdin).get("result") or [];print(r[0]["id"] if r else "")')
[ -z "$ZONE" ] && { echo "✗ Zona $DOMAIN não encontrada."; exit 1; }
LEVEL=$(curl -sS -m 20 "$API/zones/$ZONE/settings/security_level" "${H[@]}" | python3 -c 'import json,sys;print((json.load(sys.stdin).get("result") or {}).get("value","?"))')
echo "Domínio: $DOMAIN"
echo "security_level atual: $LEVEL"
case "$LEVEL" in
  under_attack) echo "🔴 BOTÃO DE PÂNICO LIGADO — site inteiro com tela de verificação. (rode ./desliga-panico.sh p/ voltar ao normal)";;
  *)           echo "🟢 Normal — verificação só nas rotas sensíveis (/login, /auth, /api).";;
esac
