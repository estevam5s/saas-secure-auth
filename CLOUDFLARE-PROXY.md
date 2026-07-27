# Cloudflare na frente do SaaS (proxy) — guia completo de ponta a ponta

Coloca um SaaS **atrás do Cloudflare como proxy DNS**, entregando:
- 🛡️ **A tela "Um momento… Executando verificação de segurança"** (Managed Challenge)
  antes das rotas sensíveis — a mesma que aparece em sites protegidos pelo Cloudflare
- 🌐 Proteção de borda (DDoS L3/L7, bot, cache) · 🔒 SSL gerenciado + HSTS

> Complementa o Turnstile (formulário) + rate-limit Upstash desta skill.
> Aqui a defesa é **na borda**, antes de chegar ao Vercel.

⚠️ **Diferença do Turnstile:** o Turnstile é um widget no `<form>` (não precisa nameserver).
Esta tela é da **borda** e **exige trocar o nameserver do domínio pro Cloudflare** — mexe
no DNS do domínio inteiro. É a parte manual; o resto é automatizado pelo script.

---

## Links (forneça estes ao usuário)
| O quê | Link |
|-------|------|
| **Adicionar site** | https://dash.cloudflare.com/?to=/:account/add-site |
| **Criar token de API** | https://dash.cloudflare.com/profile/api-tokens |
| **Painel da zona (Overview → nameservers)** | https://dash.cloudflare.com → clique no domínio |

---

## Como funciona a tela de verificação (as 3 fases)
Quando um visitante (ou bot) acessa uma rota protegida, o Cloudflare mostra, em sequência:
1. **"Executando verificação de segurança"** — página inicial escura com o nome do site.
2. **"Verificando…"** — o widget Cloudflare roda a checagem (sem interação p/ humano).
3. **"Verificação bem-sucedida. Esperando a resposta de <site>."** — libera e carrega a página.

Bots são barrados na fase 2; humanos passam em ~1-3s. Rodapé sempre traz o **Ray ID** e
"Desempenho e segurança da Cloudflare". Isso é o **Managed Challenge** — configurado no
passo 4 abaixo, mirando só `/login`, `/auth`, `/api/auth`, `/api/chat`.

---

## Passo a passo

### 1. Adicionar o domínio ao Cloudflare  ·  (usuário, manual)
1. Abra o link **Adicionar site** → digite o domínio → plano **Free** → Continuar.
2. O Cloudflare escaneia e **importa os DNS**. ⚠️ **Confira se importou TUDO** (A, CNAME,
   MX, TXT). Registros que ele NÃO importa (clássico: o **CNAME de verificação do Google
   Workspace**, ex. `xh45bnaisaq6 → gv-…googlehosted.com`) **somem quando propagar** — o
   script do passo 4 lista os registros e alerta; adicione os que faltam à mão (DNS-only).
3. Deixe o **proxy (nuvem laranja) LIGADO** no A do apex e no CNAME `www` — é o que faz o
   tráfego passar pelo Cloudflare. Registros de e-mail (MX/TXT) ficam **DNS-only** (cinza).
4. Na **Visão Geral (Overview)** anote os **2 nameservers** (ex.: `elaine.ns.cloudflare.com`,
   `terin.ns.cloudflare.com`).

### 2. Trocar o nameserver no registrador  ·  (usuário, manual)
- **Registro.br:** login → clique no domínio → **"Alterar Servidores DNS"** → há dois
  campos **Servidor 1** e **Servidor 2**:
  - **Servidor 1:** `xxxx.ns.cloudflare.com`  (o 1º valor real do Cloudflare)
  - **Servidor 2:** `yyyy.ns.cloudflare.com`  (o 2º valor real)
  - ⚠️ **Cole os ENDEREÇOS**, não a frase "1º nameserver" — senão dá "DNS desconhecido".
  - **NÃO** clique em "+ DNSSEC" (deixe DNSSEC OFF; o Cloudflare cuida depois).
  - **Salvar** (pode pedir confirmação por e-mail/token). O Registro.br mostra
    "servidores em transição — delegados em ~2h".
- **GoDaddy/Namecheap/outros:** seção "Nameservers" → "Custom/Personalizado" → cole os 2.
- **Propagação: ~30min a 2h.** A zona fica `pending` no Cloudflare e vira `active`
  (e-mail do Cloudflare) quando propagar. O SITE PODE OSCILAR nesse intervalo — é normal.

### 3. Criar o token de API  ·  (usuário, manual)
Abra o link **Criar token** → **Criar token personalizado**. Permissões (**5 linhas** —
clique "+ Adicionar mais"):
| Tipo | Recurso | Permissão |
|------|---------|-----------|
| Zona | **DNS** | Editar |
| Zona | **Configurações de zona** | Editar |
| Zona | **Serviços de firewall** | Editar |
| Zona | **WAF** | Editar |  ← **essencial p/ o Managed Challenge (rulesets)** |
| Zona | **Zona** | Ler (ou Editar) |

**Recursos de zona:** Incluir → **Zona específica** → seu domínio.
*(Se "Zona específica" estiver cinza, o domínio ainda não foi adicionado — volte ao passo 1.)*
→ Continuar → **Criar token** → copie (aparece 1x). Guarde em `~/.cf-token` (`chmod 600`).

> ⚠️ Sem a permissão **WAF**, a API de rulesets dá "Authentication error" e o Managed
> Challenge não é criado. (Aprendido na prática — "Serviços de firewall" sozinho não basta.)

### 4. Configurar TUDO via API  ·  (Claude — 1 comando)
```bash
./scripts/setup-cloudflare-proxy.sh <cf_api_token> <dominio> [rota_extra...]
# ex.: ./scripts/setup-cloudflare-proxy.sh cfut... pytrack.com.br
# rotas extras (opcional): ./scripts/setup-cloudflare-proxy.sh cfut... meusaas.com /painel /conta
```
O script faz, em ordem, e é **idempotente** (pode rodar de novo sem quebrar):
1. Acha a zona + mostra status (`active`/`pending`) e os nameservers.
2. Lista os registros DNS e **alerta** se faltar A/CNAME apex/www.
3. **SSL Full (strict)** (Vercel tem cert válido; "Flexible" causaria loop) + Always HTTPS + TLS 1.2.
4. **HSTS** (max-age 6 meses, includeSubDomains, preload — força HTTPS no navegador).
5. **Managed Challenge** (a tela de verificação) em `/login`, `/auth`, `/api/auth`, `/api/chat`
   (+ rotas extras se passar). Só desafia rotas sensíveis — visitante da home NÃO vê a tela.
6. Se a zona já estiver `active`, **valida ao vivo**: `cf-ray` na raiz, raiz=200 (normal),
   `/login`=403 (verificação ativa).

### 5. Verificar depois de propagar (zona `active`)
- Acesse `/login` → aparece a tela **"Executando verificação de segurança"**.
- Acesse a **raiz** → abre **normal** (o challenge é só nas rotas da regra).
- Loop/erro SSL? Confirme **Full (strict)**, nunca "Flexible".
- Rode o script de novo p/ ver o bloco "Validando ao vivo" com os HTTP codes.

---

## Decidir a abrangência do challenge
- **Recomendado (padrão do script):** só `/login`, `/auth`, `/api/auth`, `/api/chat` —
  protege o que importa (contas/API) sem fricção pro visitante nem dano de SEO.
- **Sob ataque real:** ligue o **botão de pânico** (`scripts/liga-panico.sh <dominio>`) —
  põe a verificação no **site inteiro** (Under Attack); `desliga-panico.sh` volta ao normal.
  Não deixe ligado permanente: penaliza SEO/conversão.

## Segurança
- Token do Cloudflare: **só em uso de API** (`~/.cf-token`/`CF_API_TOKEN`), nunca commitado
  nem no bundle. Escopo restrito à zona.
- Camadas juntas: **Cloudflare (borda) + rate-limit Upstash (app) + Turnstile (form)** =
  defesa em profundidade.
