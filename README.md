# saas-secure-auth

Skill do **Claude Code** que blinda o **login/cadastro** de um SaaS **Next.js (Vercel)** com:

- 🛡️ **Cloudflare Turnstile** — desafio "confirme que é humano" com **verificação server-side** (Secret Key só em env var). Barra criação de conta em massa e brute-force via formulário.
- ⚡ **Rate-limit global (Upstash Redis)** — contador distribuído sub-ms, isolado do banco principal, com **fallback automático** (memória ou RPC) se o Redis não estiver configurado.

Tudo **env-driven** e **fail-open**: nada quebra antes de existirem as chaves.

## Instalação

Copie a pasta para as suas skills do Claude Code:

```bash
# projeto específico
cp -r saas-secure-auth <seu-projeto>/.claude/skills/

# ou global (todos os projetos)
cp -r saas-secure-auth ~/.claude/skills/
```

Depois é só pedir ao Claude Code algo como *"proteja o login/registro desse SaaS contra bot com Turnstile e rate-limit Upstash, igual ao pytrack"* — a skill é acionada pela descrição.

📋 **Prompts prontos de comando:** veja [`PROMPT.md`](PROMPT.md).

🌐 **Camada opcional de borda** (tela "Verificação de segurança" do Cloudflare + proteção DDoS): veja [`CLOUDFLARE-PROXY.md`](CLOUDFLARE-PROXY.md).

## O que você precisa ter em mãos
- **Vercel token** (CLI).
- **Upstash management API key** + e-mail da conta (cria o Redis por API).
- **Cloudflare Turnstile**: Site Key + Secret Key de um widget do domínio do SaaS
  (crie grátis em `dash.cloudflare.com/?to=/:account/turnstile` — **não precisa de nameserver**).

## Conteúdo
```
SKILL.md                              # instruções que o Claude Code segue
CLOUDFLARE-PROXY.md                   # opcional: Cloudflare na frente do site (proxy + Managed Challenge)
PROMPT.md                             # prompts prontos de comando (copie e cole)
README.md                             # este arquivo
templates/
  turnstile.ts                        # helper verifyTurnstile (server-side)
  rate-limit-upstash.ts               # rateLimit com Upstash + fallback + prefixo por app
  api-turnstile-verify.ts             # rota p/ validar Turnstile em login client-side
  turnstile-widget.tsx.txt            # trechos do widget front-end (4 cenários)
scripts/
  create-upstash-redis.sh             # cria/reaproveita o Redis via API e imprime URL+token
  setup-vercel-env.sh                 # seta as 4 env vars em production
  setup-cloudflare-proxy.sh           # SSL + Managed Challenge numa zona Cloudflare
```

## Segurança
- **Secret Key** do Turnstile e **token do Redis**: só em **env var no Vercel**, nunca no bundle/commit.
- **Site Key**: pública (`NEXT_PUBLIC_TURNSTILE_SITE_KEY`).

## Notas
- **Upstash Free = 1 database/conta** → o script reaproveita o Redis existente; use **prefixo de chave por app** (`<app>:rl:...`) para vários SaaS compartilharem.
- **Vercel Hobby**: 12 funções serverless/deploy e 100 deploys/dia — a SKILL.md explica como contornar.

---
Feito por [estevam5s](https://github.com/estevam5s). Derivado da implementação real em pytrack.com.br e linkium.me.
