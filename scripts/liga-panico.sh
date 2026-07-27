#!/bin/bash
# 🔴 BOTÃO DE PÂNICO — LIGA a proteção máxima do Cloudflare no site INTEIRO.
# Ativa o "Under Attack Mode": TODA página passa a exigir a tela "Executando
# verificação de segurança" antes de carregar. Use SÓ durante um ataque real
# (DDoS / enxurrada de bots). Lembre de DESLIGAR depois (desliga-panico.sh),
# senão prejudica SEO e afasta visitantes legítimos.
#
# Uso:
#   ./liga-panico.sh <dominio>
#   ./liga-panico.sh pytrack.com.br
#
# Requer o token de API do Cloudflare (com permissão Zona: Configurações de zona → Editar).
# Coloque o token no arquivo ~/.cf-token OU exporte CF_API_TOKEN antes de rodar.
set -euo pipefail

DOMAIN="${1:?Informe o domínio. Ex: ./liga-panico.sh pytrack.com.br}"
CFTOK="${CF_API_TOKEN:-$(cat "$HOME/.cf-token" 2>/dev/null || true)}"
[ -z "${CFTOK:-}" ] && { echo "✗ Token do Cloudflare não encontrado. Exporte CF_API_TOKEN ou salve em ~/.cf-token"; exit 1; }

API="https://api.cloudflare.com/client/v4"
H=(-H "Authorization: Bearer $CFTOK" -H "Content-Type: application/json")

ZONE=$(curl -sS -m 20 "$API/zones?name=$DOMAIN" "${H[@]}" | python3 -c 'import json,sys;r=json.load(sys.stdin).get("result") or [];print(r[0]["id"] if r else "")')
[ -z "$ZONE" ] && { echo "✗ Zona $DOMAIN não encontrada nessa conta Cloudflare."; exit 1; }

echo "🔴 Ligando MODO DE ATAQUE (Under Attack) em $DOMAIN ..."
RESP=$(curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/security_level" "${H[@]}" -d '{"value":"under_attack"}')
OK=$(echo "$RESP" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("success"))')
if [ "$OK" = "True" ]; then
  echo "✅ ATIVADO. O site inteiro agora mostra a tela de verificação de segurança."
  echo "   ⚠️  Lembre de rodar ./desliga-panico.sh $DOMAIN quando o ataque passar."
else
  echo "✗ Falhou: $RESP"
  exit 1
fi
