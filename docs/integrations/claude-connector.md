# Conector do agencios para o Claude

Conecte o **agencios** ao **Claude** e opere sua agência por linguagem natural — crie e mova
tickets, gere criativos, agende posts, gerencie clientes e cobranças, tudo conversando com o Claude.

O conector é um **servidor MCP remoto** (Streamable HTTP). Você adiciona ao Claude colando **uma
URL pessoal** — a credencial já vai embutida na URL, então **não há login nem OAuth**: cola e funciona.

---

## Pré-requisitos

- Uma conta **agencios** com acesso a pelo menos um workspace.
- Um plano do Claude que permite **conectores personalizados** (Claude Pro, Team ou Enterprise),
  no **Claude.ai** (web) ou no **Claude Desktop**.

---

## Passo 1 — Copie sua URL do conector no agencios

1. Abra o agencios e vá em **Configurações** (`/configuracoes`).
2. Aba **Conexões** → cartão **Conector do Claude**.
3. Clique em **Revelar** e depois **Copiar**. A URL tem este formato:

   ```
   https://SEU-DOMINIO/mcp/c/agc_xxxxxxxxxxxxxxxxxxxxxxxx
   ```

> ⚠️ **Essa URL é um segredo.** Quem tiver a URL opera seus workspaces com as **suas permissões**.
> Não compartilhe nem cole em lugares públicos. Se vazar, clique em **Gerar nova URL** (a anterior
> deixa de funcionar imediatamente).

---

## Passo 2 — Adicione o conector no Claude

### Claude.ai (web)

1. Abra **Settings → Connectors** (Configurações → Conectores).
2. Clique em **Add custom connector** (Adicionar conector personalizado).
3. Em **URL**, cole a URL copiada no Passo 1.
4. Confirme. O Claude conecta direto — **não pede login**, pois a credencial está na URL.
5. Numa conversa, habilite o conector **agencios** no menu de ferramentas/conectores.

### Claude Desktop

Adicione um servidor MCP remoto apontando para a mesma URL (Settings → Connectors → Add). Se a sua
versão usa arquivo de configuração, use um entry de servidor remoto com a URL acima.

---

## Passo 3 — Use

Depois de conectado, basta pedir em linguagem natural. Como sua conta pode ter mais de um workspace,
comece descobrindo os workspaces disponíveis:

- *"Liste meus workspaces no agencios."* → o Claude chama `list_workspaces` e mostra os **slugs**.
- *"No workspace `estudio-pulse`, liste os tickets em produção."*
- *"Crie um ticket no projeto Bloom com o título 'Reel de lançamento'."*
- *"Quais reuniões eu tenho essa semana?"*
- *"Gere um carrossel para o ticket #123."*
- *"Marque a cobrança da Bloom como paga."*

O Claude sempre resolve a permissão pelo **seu papel** naquele workspace — ele não consegue fazer
nada que você mesmo não poderia fazer pela interface.

---

## O que o conector pode fazer

O servidor expõe o catálogo completo de ferramentas do agencios, entre elas:

| Área | Exemplos de ferramentas |
|---|---|
| Quadro & tickets | `get_board`, `list_tickets`, `create_ticket`, `advance_ticket`, `summarize_ticket` |
| Subtarefas & notas | `create_subtask`, `update_subtask`, `create_note` |
| Clientes & projetos | `list_clients`, `create_client`, `list_projects`, `create_project` |
| Estúdio / criativos | `studio_generate`, `generate_creative`, `list_generations` |
| Publicação | `list_posts`, `create_post`, `list_social_accounts` |
| Calendário & reuniões | `get_calendar`, `list_meetings`, `create_meeting` |
| Cobranças | `list_invoices`, `create_invoice`, `mark_invoice_paid`, `generate_invoice_payment_link` |
| Conta | `list_workspaces`, `me`, `get_settings`, `list_members` |

---

## Segurança & rotação

- A URL contém um **token pessoal** (prefixo `agc_`). Ele identifica **você**; o Claude age como você.
- Para invalidar a URL atual (ex.: suspeita de vazamento), use **Gerar nova URL** no cartão do
  conector. Depois disso, **readicione** a nova URL no Claude — a antiga retorna erro 401.
- O acesso é por **usuário**, não por dispositivo: a mesma URL funciona onde você colar.

---

## Solução de problemas

| Sintoma | Causa provável / solução |
|---|---|
| Claude diz "connector failed" ou 401 | URL incompleta ou token rotacionado. Copie a URL de novo no agencios e readicione. |
| Claude tenta abrir uma tela de login/OAuth | Você colou a URL **base** `…/mcp` (fluxo OAuth). Use a URL **tokenizada** `…/mcp/c/agc_…` do cartão **Conector do Claude**. |
| "You are not a member of …" | O slug do workspace está errado. Peça *"liste meus workspaces"* e use o slug exato. |
| Uma ação é recusada | Seu papel no workspace não permite. Ações seguem as mesmas regras da interface. |

---

## Nota técnica (para desenvolvedores)

- Endpoint tokenizado: `POST /mcp/c/:token` (Streamable HTTP, JSON-RPC 2.0) — `Mcp::ConnectorController`,
  que reaproveita o `Mcp::Dispatcher` e o catálogo de ferramentas do endpoint OAuth (`/mcp`).
- O token vive em `users.mcp_connector_token` (gerado sob demanda, rotacionável) e concede escopo
  `read write`; a autorização fina continua por workspace via Pundit + `Mcp::ToolContext`.
- A URL é montada com `SystemConfig.app_host`. Em produção, garanta que `APP_HOST` aponte para o
  domínio público (ver `CLAUDE.md`).
