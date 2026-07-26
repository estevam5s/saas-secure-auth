#!/bin/bash
# Cria (ou reaproveita) um Redis global no Upstash via management API e imprime
# a REST URL + REST token. Free = 1 DB por conta → se já existir, reaproveita e
# recomenda prefixo de chave por app.
# Uso: create-upstash-redis.sh <email> <api_key> [nome-do-db]
set -euo pipefail
EMAIL="${1:?email da conta Upstash}"
APIKEY="${2:?management API key do Upstash}"
NAME="${3:-saas-ratelimit}"

api() { curl -sS -m 30 -u "$EMAIL:$APIKEY" "https://api.upstash.com/v2/redis/$1" "${@:2}"; }

# já existe algum DB? (free permite só 1)
EXISTING="$(api databases)"
COUNT="$(echo "$EXISTING" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"

if [ "$COUNT" -ge 1 ]; then
  DBID="$(echo "$EXISTING" | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["database_id"])')"
  echo "ℹ️  Já existe um Redis (free = 1 DB). Reaproveitando — use PREFIXO de chave por app (ex.: <app>:rl:...)."
else
  R="$(api database -X POST -H 'Content-Type: application/json' \
        -d "{\"name\":\"$NAME\",\"region\":\"global\",\"primary_region\":\"us-east-1\",\"tls\":true}")"
  DBID="$(echo "$R" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("database_id",""))')"
  [ -z "$DBID" ] && { echo "✗ Falha ao criar: $R"; exit 1; }
  echo "✅ Redis criado: $NAME"
fi

DET="$(api "database/$DBID")"
python3 - "$DET" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
print("UPSTASH_REDIS_REST_URL=https://%s" % d["endpoint"])
print("UPSTASH_REDIS_REST_TOKEN=%s" % d["rest_token"])
PY
echo "→ Teste: curl \$UPSTASH_REDIS_REST_URL/ping -H \"Authorization: Bearer \$UPSTASH_REDIS_REST_TOKEN\"  (espera PONG)"
