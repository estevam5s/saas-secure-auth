---
name: saas-secure-auth
description: Protege o login/cadastro de um SaaS Next.js contra bots com Cloudflare Turnstile (widget + verificação server-side) e adiciona rate-limit global com Upstash Redis (fallback automático), preparando as env vars no Vercel. Use quando pedirem "proteger login/registro contra bot", "adicionar Turnstile", "Cloudflare no login", "rate-limit robusto", "Upstash/Redis" ou "igual ao pytrack".
---

# saas-secure-auth — Anti-bot (Turnstile) + Rate-limit (Upstash) para SaaS Next.js

Adiciona duas camadas de segurança a um SaaS Next.js hospedado no Vercel:

1. **Cloudflare Turnstile** — desafio "confirme que é humano" no login/cadastro, com **verificação server-side** (a Secret Key só vive em env var). Barra criação de conta em massa e brute-force via formulário.
2. **Rate-limit global (Upstash Redis)** — contador distribuído sub-ms, isolado do banco principal, com **fallback automático** (em memória ou no RPC atual) se o Redis não estiver configurado.

Nada quebra antes das chaves existirem: todo o código é **env-driven** e **fail-open** na ausência de config.

---

## Pré-requisitos e credenciais
- **Vercel token** (CLI) + `--scope`. Descubra o projeto real com `vercel inspect <domínio>` — **NUNCA chute o nome do projeto pelo domínio** (o domínio pode ter prefixo ≠ nome do projeto; deployar no projeto errado quebra produção).
- **Upstash management API key** + o e-mail da conta (Basic auth `EMAIL:APIKEY`). Cria o Redis por API.
- **Cloudflare Turnstile**: precisa de um **widget** por domínio (Site Key pública + Secret Key). Opções:
  - **Manual** (mais simples): o usuário cria em `dash.cloudflare.com/?to=/:account/turnstile` → Add widget → hostnames do SaaS → Managed → copia Site Key + Secret Key. **Não precisa de nameserver nem domínio verificado.**
  - **API** (se houver Cloudflare API token + account id): `POST /accounts/{account}/challenges/widgets` com `{ name, domains, mode: "managed" }`.

⚠️ **Segredos**: Secret Key do Turnstile e token REST do Redis vão **só em env var no Vercel**, nunca no bundle/commit. A Site Key é pública (pode ir no bundle via `NEXT_PUBLIC_`).

---

## Passo a passo

### 1. Descobrir o fluxo de auth do SaaS
Procure como o login/cadastro é feito — muda ONDE se valida o Turnstile:
- **Server Action** (`app/auth/actions.ts` com `signIn`/`signUp`): valida o token **dentro da action** (padrão pytrack). O widget injeta o hidden input `cf-turnstile-response` no `<form>` → leia `formData.get("cf-turnstile-response")`.
- **API Route** de registro (`app/api/auth/register`): valida no handler lendo `body.turnstileToken`.
- **Login client-side** (`supabase.auth.signInWithPassword` no cliente): não há rota; crie `app/api/auth/turnstile/route.ts` que só verifica o token, e chame ANTES do `signInWithPassword`.
- **Componente compartilhado** (ex.: `AuthExperience`): adicione uma prop opcional `turnstileSiteKey`; renderize o widget dentro do `<form>` e passe o token aos callbacks (`onLogin`/`onRegister`). Retrocompatível — outros SaaS que não passam a prop seguem iguais.

### 2. Copiar os templates
- `templates/turnstile.ts` → `lib/turnstile.ts` (helper `verifyTurnstile`).
- `templates/rate-limit-upstash.ts` → `lib/rate-limit.ts` **adaptando ao formato existente**:
  - Se o projeto já tem `rateLimit(key, limit, windowSec) -> boolean` (RPC/Postgres, estilo pytrack): mantenha a assinatura, tente Redis primeiro e caia no comportamento antigo.
  - Se é `rateLimit(key, max, windowMs) -> {ok,remaining,retryAfter}` síncrono em memória (estilo linkium): torne **async**, prefixe as chaves com `<app>:rl:` e **atualize todos os call sites para `await`**.
- `templates/api-turnstile-verify.ts` → `app/api/auth/turnstile/route.ts` (só quando o login é client-side).

### 3. Integrar
- Import + chamada de `verifyTurnstile(token, ip)` no início da action/rota de login e cadastro. Erro → retornar "Verificação anti-robô falhou. Recarregue a página e tente novamente."
- Front: carregar `https://challenges.cloudflare.com/turnstile/v0/api.js` (next/script ou `<script async defer>`) e renderizar `<div class="cf-turnstile" data-sitekey={NEXT_PUBLIC_TURNSTILE_SITE_KEY} data-theme="auto" data-language="pt-br" data-size="flexible" />` dentro do form. O widget injeta `cf-turnstile-response` automaticamente; no client-side, leia via `window.turnstile.getResponse()` no submit e `window.turnstile.reset()` depois.
- Dependência: `@upstash/redis@^1.34.9` no `package.json`.

### 4. Liberar o CSP
Adicione `https://challenges.cloudflare.com` em **script-src**, **connect-src** e **frame-src** (no `next.config.*` ou `vercel.json`). Sem isso o widget não carrega.

### 5. Criar o Redis (Upstash) por API
Rode `scripts/create-upstash-redis.sh <email> <api_key> <nome-do-db>`. Ele cria um Redis **global** e imprime a REST URL + REST token.
⚠️ **Free = 1 database por conta.** Se já existir um, **compartilhe o mesmo Redis** entre SaaS usando **prefixo de chave** (`<app>:rl:...`) — não crie outro. O script detecta e reaproveita.

### 6. Setar as env vars no Vercel
Rode `scripts/setup-vercel-env.sh <vercel_token> <projeto> <redis_url> <redis_token> <turnstile_site_key> <turnstile_secret_key>`.
Setar TODAS em **production** ANTES do deploy (a `NEXT_PUBLIC_TURNSTILE_SITE_KEY` é inlinada no build):
- `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` (ou `KV_REST_API_URL`/`KV_REST_API_TOKEN`)
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY` (pública), `TURNSTILE_SECRET_KEY` (secreta, server-only)

### 7. Deploy
- **Limpe o lixo `._*` RECURSIVO** antes (`find . -path ./node_modules -prune -o -name '._*' -delete`) — em pendrive FAT32 o editar arquivos gera `._foo.ts` que o ESLint tenta parsear → **"Parsing error: Invalid character"** e o build FALHA. `-maxdepth 2` não pega os fundos.
- `vercel --prod` no **projeto correto** (via `vercel inspect`), depois `vercel alias set <deploy> <domínio>`.
- **Confirme o status Ready** (`vercel ls <proj> | grep Ready`) — um deploy com erro ainda gera URL, então cheque o status; NÃO marque OK só por ter URL.

---

## Armadilhas conhecidas (aprendidas na prática)
- **Nome do projeto ≠ domínio** → sempre `vercel inspect <domínio>`. (Já quebrou produção do concurso deployando `aprovacao-concurso-publico` quando o projeto era `concurso-publico`.)
- **`._*` do FAT32** → limpar recursivo antes do build.
- **Limite Hobby: 12 funções serverless/deploy** → se estourar, funda a nova rota numa função existente (ex.: dispatch por `?action=support` num `/api/track`).
- **Limite Hobby: 100 deploys/dia** → deploys em excesso bloqueiam ("Resource is limited"); use retry com espera de ~25min, ou Vercel Pro.
- **Supabase Auth CAPTCHA nativo** (`signInWithPassword({ options: { captchaToken } })`) só serve se você tiver acesso ao dashboard do Supabase pra ligar o CAPTCHA; se a conta estiver restrita, use a rota de verify server-side.
- **fail-open vs fail-closed**: sem config → não bloqueia; configurado e token ausente/inválido → bloqueia; erro de rede na verificação → não bloqueia (não derruba usuário legítimo).

## Verificação final (browser)
- Widget "confirme que é humano" aparece no login/cadastro.
- Enviar sem passar o desafio → erro anti-robô.
- Rate-limit: ver chaves `<app>:rl:*` no Redis (Upstash console ou `GET /dbsize`).
