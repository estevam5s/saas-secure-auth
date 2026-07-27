#!/bin/bash
# ============================================================================
# Configura TODA a camada Cloudflare de um SaaS já adicionado à conta (proxy):
#   1. Verifica a zona e o status (active/pending)
#   2. Confere os registros DNS e alerta sobre os que faltam (ex.: CNAME do Google)
#   3. SSL/TLS Full (strict) + Always HTTPS + TLS mínimo 1.2
#   4. HSTS (força HTTPS no navegador)
#   5. Managed Challenge (a tela "Executando verificação de segurança")
#      nas rotas sensíveis: /login, /auth, /api/auth, /api/chat
#   6. Valida ao vivo: cf-ray na raiz + challenge no /login
#
# Pré: domínio adicionado ao Cloudflare + nameserver trocado no registrador
#      (ver CLOUDFLARE-PROXY.md, passos 1-3). Token com permissões:
#      Zona → DNS / Configurações de zona / Serviços de firewall / WAF / Zona.
#
# Uso:  ./setup-cloudflare-proxy.sh <cf_api_token> <dominio> [rota_extra...]
#   ./setup-cloudflare-proxy.sh cfut... pytrack.com.br
#   ./setup-cloudflare-proxy.sh cfut... meusaas.com /painel /conta   # rotas extra no challenge
# ============================================================================
set -euo pipefail
CFTOK="${1:?token de API do Cloudflare}"
DOMAIN="${2:?domínio, ex: meusaas.com}"
shift 2 || true
EXTRA_ROUTES=("$@")   # rotas adicionais para o challenge, além das padrão

API="https://api.cloudflare.com/client/v4"
H=(-H "Authorization: Bearer $CFTOK" -H "Content-Type: application/json")
ok() { python3 -c 'import json,sys;d=json.load(sys.stdin);print("  ✅" if d.get("success") else "  ✗ "+str(d.get("errors")))'; }

echo "════════════════════════════════════════════════════════════"
echo " Configurando Cloudflare para: $DOMAIN"
echo "════════════════════════════════════════════════════════════"

# ---- 1. zona + status --------------------------------------------------------
ZDATA=$(curl -sS -m 20 "$API/zones?name=$DOMAIN" "${H[@]}")
ZONE=$(echo "$ZDATA" | python3 -c 'import json,sys;r=json.load(sys.stdin).get("result") or [];print(r[0]["id"] if r else "")')
[ -z "$ZONE" ] && { echo "✗ Zona $DOMAIN não encontrada. Adicione o site no Cloudflare primeiro (dash → Adicionar site)."; exit 1; }
STATUS=$(echo "$ZDATA" | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"][0]["status"])')
NS=$(echo "$ZDATA" | python3 -c 'import json,sys;print(", ".join(json.load(sys.stdin)["result"][0].get("name_servers",[])))')
echo "▸ Zona:   $ZONE"
echo "▸ Status: $STATUS  $([ "$STATUS" != active ] && echo '(pending — troque o nameserver no registrador; config aplica ao propagar)')"
echo "▸ Nameservers Cloudflare: $NS"

# ---- 2. checa registros DNS (alerta os que faltam) ---------------------------
echo "▸ Registros DNS na zona:"
curl -sS -m 20 "$API/zones/$ZONE/dns_records?per_page=100" "${H[@]}" | python3 -c '
import json,sys
d=json.load(sys.stdin).get("result",[])
prox={True:"proxy",False:"dns"}
for r in d:
    t=r["type"]; nm=r["name"]
    tag=prox.get(r.get("proxied"),"") if t in ("A","AAAA","CNAME") else ""
    print("    %-6s %-34s %s" % (t, nm, tag))
print("    total: %d" % len(d))
if not any(r["type"]=="A" or (r["type"]=="CNAME" and r["name"].startswith("www")) for r in d):
    print("    !! Nenhum A/CNAME apex/www - o site pode nao resolver. Confira a importacao.")
'
echo "    (atencao: registros de e-mail/verificacao NAO importados somem ao propagar — adicione-os na mao)"

# ---- 3. SSL + HTTPS ----------------------------------------------------------
echo "▸ SSL Full (strict):"; curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/ssl" "${H[@]}" -d '{"value":"strict"}' | ok
echo "▸ Always Use HTTPS:";  curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/always_use_https" "${H[@]}" -d '{"value":"on"}' | ok
echo "▸ TLS mínimo 1.2:";    curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/min_tls_version" "${H[@]}" -d '{"value":"1.2"}' | ok

# ---- 4. HSTS -----------------------------------------------------------------
echo "▸ HSTS (força HTTPS no navegador, 6 meses, preload):"
curl -sS -m 20 -X PATCH "$API/zones/$ZONE/settings/security_header" "${H[@]}" -d '{
  "value":{"strict_transport_security":{"enabled":true,"max_age":15552000,"include_subdomains":true,"preload":true,"nosniff":true}}}' | ok

# ---- 5. Managed Challenge (a tela de verificação) ----------------------------
# expressão: rotas sensíveis padrão + extras passadas na linha de comando
EXPR='(http.request.uri.path contains "/login") or (http.request.uri.path contains "/auth") or (starts_with(http.request.uri.path,"/api/auth")) or (starts_with(http.request.uri.path,"/api/chat"))'
for r in ${EXTRA_ROUTES[@]+"${EXTRA_ROUTES[@]}"}; do EXPR="$EXPR or (http.request.uri.path contains \"$r\")"; done
echo "▸ Managed Challenge (a tela 'Executando verificação de segurança'):"
echo "    rotas: /login, /auth, /api/auth, /api/chat ${EXTRA_ROUTES[*]+, ${EXTRA_ROUTES[*]}}"
# monta o JSON com Python (escapa a expressão corretamente, sem quebras de linha no payload)
CHALLENGE_BODY=$(python3 -c 'import json,sys;print(json.dumps({"rules":[{"action":"managed_challenge","expression":sys.argv[1],"description":"Managed Challenge em login/auth (anti-bot na borda)","enabled":True}]}))' "$EXPR")
curl -sS -m 25 -X PUT "$API/zones/$ZONE/rulesets/phases/http_request_firewall_custom/entrypoint" "${H[@]}" -d "$CHALLENGE_BODY" | ok

# ---- 6. validação ao vivo (só se a zona já estiver active) -------------------
if [ "$STATUS" = active ]; then
  echo "▸ Validando ao vivo:"
  RAY=$(curl -sS -m 15 -I "https://$DOMAIN/" 2>/dev/null | grep -io 'cf-ray' | head -1)
  ROOT=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "https://$DOMAIN/" 2>/dev/null)
  LOGIN=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "https://$DOMAIN/login" 2>/dev/null)
  echo "    passa pelo Cloudflare (cf-ray): ${RAY:+SIM}${RAY:-NAO (ainda no host antigo?)}"
  echo "    raiz do site: HTTP $ROOT  $(case "$ROOT" in 200|301|302|308) echo '(abre normal)';; esac)"
  echo "    /login:       HTTP $LOGIN $([ "$LOGIN" = 403 ] && echo '(tela de verificacao ativa)')"
else
  echo "▸ Zona pending — rode de novo após propagar (~30min-2h) para a validação ao vivo."
fi
echo "════════════════════════════════════════════════════════════"
echo " Concluído. Quando 'active': raiz=200 (normal), /login=403 (verificação)."
echo "════════════════════════════════════════════════════════════"
