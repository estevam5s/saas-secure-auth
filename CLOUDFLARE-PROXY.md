# Cloudflare na frente do SaaS (proxy) + tela "Verificação de segurança"

Guia para colocar um SaaS **atrás do Cloudflare como proxy DNS**, ganhando:
- 🛡️ **Managed Challenge** — a tela *"Um momento… Executando verificação de segurança"* (Cloudflare) antes de rotas sensíveis
- 🌐 Proteção de borda (DDoS L3/L7, bot filtering, cache)
- 🔒 SSL gerenciado

> Complementa o Turnstile (no formulário) + rate-limit Upstash. Aqui a proteção é **na borda**, antes de chegar no Vercel.

⚠️ **Diferença do Turnstile:** o Turnstile é um widget no `<form>` (não precisa nameserver). Esta tela é da **borda** e **exige trocar o nameserver do domínio pro Cloudflare**. É mais invasivo — mexe no DNS do domínio inteiro.

---

## Links úteis
- **Adicionar site ao Cloudflare:** https://dash.cloudflare.com/?to=/:account/add-site
- **Criar token de API:** https://dash.cloudflare.com/profile/api-tokens
- **Painel da zona (Overview, nameservers):** https://dash.cloudflare.com → clique no domínio

---

## Passo a passo

### 1. Adicionar o domínio ao Cloudflare (você, manual)
1. https://dash.cloudflare.com/?to=/:account/add-site → digite o domínio → **Free** → Continuar.
2. O Cloudflare escaneia e importa os DNS. **Confira se importou TUDO** (A, CNAME, MX, TXT). Registros que ele NÃO importa (ex.: CNAME de verificação do Google Workspace) somem quando propagar → adicione-os na mão antes.
3. Na **Visão Geral (Overview)**, anote os **2 nameservers** atribuídos (ex.: `elaine.ns.cloudflare.com`, `terin.ns.cloudflare.com`).

### 2. Trocar o nameserver no registrador (você, manual)
- **Registro.br:** login → clique no domínio → **"Alterar Servidores DNS"** → cole os **valores reais** do Cloudflare:
  - **Servidor 1:** `xxxx.ns.cloudflare.com`
  - **Servidor 2:** `yyyy.ns.cloudflare.com`
  - **NÃO** ligue DNSSEC aqui (deixe OFF; o Cloudflare cuida depois). **Salvar**.
  - ⚠️ Cole os ENDEREÇOS, não a frase "1º nameserver" — senão dá "DNS desconhecido".
- Outros registradores (GoDaddy/Namecheap): seção "Nameservers" → "Custom" → cole os 2.
- **Propagação: ~30min a 2h.** A zona fica `pending` até ativar (e-mail do Cloudflare quando virar `active`).

### 3. Criar o token de API (você, manual)
https://dash.cloudflare.com/profile/api-tokens → **Criar token personalizado**. Permissões (**5**):
| Tipo | Recurso | Permissão |
|------|---------|-----------|
| Zona | **DNS** | Editar |
| Zona | **Configurações de zona** | Editar |
| Zona | **Serviços de firewall** | Editar |
| Zona | **WAF** | Editar |  ← **essencial p/ o Managed Challenge (rulesets)** |
| Zona | **Zona** | Ler (ou Editar) |

**Recursos de zona:** Incluir → **Zona específica** → seu domínio. → Criar → copie o token.

> ⚠️ Sem a permissão **WAF**, a API de rulesets dá "Authentication error" e o Managed Challenge não pode ser criado. (Aprendido no pytrack.)

### 4. Configurar via API (Claude faz — comandos abaixo)
Com `CFTOK` (token) e `ZONE` (id da zona, de `GET /zones?name=<domínio>`):

```bash
# SSL Full (strict) — Vercel tem cert válido; "Flexible" causa loop de redirect
curl -X PATCH ".../zones/$ZONE/settings/ssl" -H "Authorization: Bearer $CFTOK" \
  -H "Content-Type: application/json" -d '{"value":"strict"}'
# Always HTTPS + TLS mínimo 1.2
curl -X PATCH ".../zones/$ZONE/settings/always_use_https" ... -d '{"value":"on"}'
curl -X PATCH ".../zones/$ZONE/settings/min_tls_version" ... -d '{"value":"1.2"}'

# Managed Challenge SÓ em rotas sensíveis (não atrapalha o visitante normal):
curl -X PUT ".../zones/$ZONE/rulesets/phases/http_request_firewall_custom/entrypoint" \
  -H "Authorization: Bearer $CFTOK" -H "Content-Type: application/json" -d '{
    "rules":[{"action":"managed_challenge",
      "expression":"(http.request.uri.path contains \"/login\") or (http.request.uri.path contains \"/auth\") or (starts_with(http.request.uri.path,\"/api/auth\")) or (starts_with(http.request.uri.path,\"/api/chat\"))",
      "description":"Managed Challenge em login/auth","enabled":true}]}'
```
(Base URL: `https://api.cloudflare.com/client/v4`)

### 5. Após propagar (zona `active`)
- Acesse `/login` → deve aparecer a tela **"Executando verificação de segurança"**.
- Acesse a **raiz** do site → deve abrir **normal** (challenge só nas rotas da regra).
- Se der loop/erro SSL: confirme **Full (strict)**, não "Flexible".

---

## Decisão importante: onde aplicar o challenge
- **Recomendado (feito no pytrack):** Managed Challenge **só em `/login`, `/auth`, `/api/auth`, `/api/chat`** — protege o que importa sem fricção pro visitante nem dano de SEO.
- **Só sob ataque real:** `security_level: under_attack` (Zone Settings) liga a tela pra **todo** o site. Agressivo — desligue quando o ataque passar.

## Segurança
- Token do Cloudflare: **só em uso de API**, nunca commitado/bundle. Escopo restrito à zona.
- Combine com Turnstile (form) + rate-limit Upstash desta skill = defesa em camadas (borda + app + form).
