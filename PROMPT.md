# Prompts de comando — saas-secure-auth

Prompts prontos para acionar a skill **saas-secure-auth** no Claude Code em qualquer
SaaS Next.js. Copie, cole e ajuste o que estiver `<entre colchetes>`.

---

## 🚀 Prompt principal (copie este)

```
Use a skill saas-secure-auth para proteger o login e o cadastro do SaaS
<NOME/URL do SaaS, ex: https://meusaas.vercel.app>.

Faça igual ao pytrack/linkium:
1. Cloudflare Turnstile (anti-bot) no login E no cadastro, com verificação
   server-side (Secret Key só em env var, nunca no bundle).
2. Rate-limit global com Upstash Redis, com fallback automático.
3. Prepare as env vars no Vercel (production) e faça o deploy no projeto correto
   (resolva o projeto por `vercel inspect <domínio>`, não chute pelo domínio).

Antes de começar, detecte como o SaaS faz auth (server action, api route ou
login client-side) e adapte a validação do Turnstile ao fluxo.
No fim, verifique no navegador que o widget aparece e que um envio sem o desafio
é bloqueado.
```

---

## 🔑 Credenciais que o Claude vai pedir (tenha em mãos)

- **Vercel token** (CLI) — para setar env vars e deployar.
- **Upstash management API key + e-mail da conta** — para criar/reaproveitar o Redis por API.
  *(Free = 1 database por conta → se já houver um, ele reaproveita com prefixo de chave.)*
- **Cloudflare Turnstile: Site Key + Secret Key** — crie um widget grátis em
  `dash.cloudflare.com/?to=/:account/turnstile`:
  - Add widget → nome do SaaS
  - **Nomes de host:** o domínio e o `www` (ex.: `meusaas.com` e `www.meusaas.com`) — só o hostname, sem `https://` nem caminho
  - Modo: **Gerenciado** (recomendado) → Criar → copie as duas chaves
  - *(Não precisa de nameserver nem domínio verificado.)*

---

## Variações de prompt

### Só o anti-bot (sem mexer no rate-limit)
```
Use a skill saas-secure-auth para adicionar apenas o Cloudflare Turnstile no
login e cadastro do <SaaS>, com verificação server-side. Não altere o rate-limit
existente.
```

### Só o rate-limit robusto (sem Turnstile)
```
Use a skill saas-secure-auth para trocar o rate-limit do <SaaS> por Upstash Redis
(global, com fallback), reaproveitando o Redis existente com prefixo de chave.
Não adicione Turnstile.
```

### Proteger também outra rota (ex.: reset de senha, /api/chat)
```
Use a skill saas-secure-auth no <SaaS> e, além do login/cadastro, aplique a
verificação do Turnstile também na rota <ex: /api/reset-password> e rate-limit
na rota <ex: /api/chat>.
```

### Já tenho as chaves (passa direto)
```
Use a skill saas-secure-auth no <SaaS>. Chaves prontas:
- Turnstile Site Key: <0x...>
- Turnstile Secret Key: <0x...>  (server-only)
- Redis: reaproveite o existente com prefixo "<app>:rl:"
Configure as env vars no Vercel e faça o deploy.
```

---

## O que esperar como resultado

- `lib/turnstile.ts` (verify server-side) + `lib/rate-limit.ts` (Upstash + fallback).
- Widget Turnstile no formulário de login/cadastro (só carrega se a Site Key existir).
- Rota de verify (se o login for client-side).
- CSP liberando `challenges.cloudflare.com`.
- Env vars no Vercel: `NEXT_PUBLIC_TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY`,
  `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`.
- Deploy no projeto correto + verificação no navegador.

> ⚠️ Tudo é **fail-open** sem as chaves: dá pra plugar o código primeiro e ativar
> depois, sem quebrar o site.
