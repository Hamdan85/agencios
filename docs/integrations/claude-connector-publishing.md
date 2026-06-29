# Publicar o conector do agencios no diretório do Claude

> Pesquisado e verificado em **2026-06** contra a documentação oficial da Anthropic. O processo e os
> requisitos mudam — **reconfirme** nos links em *Fontes* antes de submeter.

Há **dois caminhos** para o agencios chegar no Claude:

1. **Conector personalizado (self-serve)** — o usuário cola a própria URL. Já implementado e
   documentado em [`claude-connector.md`](./claude-connector.md). Não exige aprovação da Anthropic.
2. **Conector listado no diretório** — aparece na lista de conectores do Claude para todos os
   usuários, com um botão **Connect**. Exige **submissão e revisão pela Anthropic**. É disso que
   este documento trata.

---

## 1. Elegibilidade

- **Organização Team ou Enterprise** no Claude (o Admin settings não existe em planos individuais).
- Por padrão, só **Owners / Primary owners** submetem e gerenciam listagens. No Enterprise, um Owner
  pode delegar criando um papel com a permissão **Directory management**.
- Portal de submissão: **`https://claude.ai/admin-settings/directory/submissions/new`**.

---

## 2. Pré-requisitos do lado do agencios

### Infra
- **Domínio público HTTPS estável** — o servidor MCP precisa ser alcançável pela internet pública a
  partir das **faixas de IP da Anthropic**. Túnel de dev (ngrok) **não serve**: use o domínio de
  produção e configure `APP_HOST` para ele (ver `CLAUDE.md`). Nada de VPN/firewall bloqueando.
- **Transporte**: Streamable HTTP — já temos (`POST /mcp`, `Mcp::ServerController`).

### Autenticação (escolha um)
O portal pergunta se **todos os usuários conectam na mesma URL** ou **URLs diferentes por usuário**,
e qual o método de auth (**OAuth 2.0**, *custom connection* ou *no auth*).

- **Recomendado para o diretório → OAuth 2.0** (URL única + botão *Connect*). O agencios **já tem**
  isso: provider OAuth 2.1 (Doorkeeper) + Dynamic Client Registration + discovery, no mesmo `/mcp`:
  - `GET /.well-known/oauth-protected-resource`
  - `GET /.well-known/oauth-authorization-server`
  - `POST /oauth/register` (DCR), `/oauth/authorize`, `/oauth/token`
  - O servidor responde **401 + `WWW-Authenticate`** quando sem token → é isso que dispara o fluxo.
- **Alternativa → *custom connection* (URL por usuário)**: o conector tokenizado `/mcp/c/:token`
  ([`claude-connector.md`](./claude-connector.md)). Bom para "URLs diferentes por usuário", mas o
  diretório tende a preferir OAuth para a experiência de um clique.

### Ferramentas (já atendido, conferir antes de submeter)
- Toda tool tem **`title`** e o hint aplicável **`readOnlyHint`** (leitura) ou **`destructiveHint`**
  (destrutiva) — o `Mcp::Dispatcher#annotations_for` já emite isso.
- **Nomes ≤ 64 caracteres** — ok (o maior hoje é `generate_invoice_payment_link`, 29).
- **Leitura e escrita separadas** — uma tool que mistura GET com POST/PUT/PATCH/DELETE é rejeitada.
- **Descrições honestas** — o revisor testa cada tool; descrição vaga ("faz uma requisição") reprova.
- **Sem prompt-injection** nas descrições (nada de instruir o Claude a chamar outras tools, puxar
  instruções externas, diretivas ocultas, etc.).
- **Validação de input** com mensagens de erro acionáveis; respostas no tamanho da tarefa (sem
  "data dumps"); não coletar histórico/memória/arquivos do usuário.

### Assets para preencher o portal
- **Server URL** (HTTPS de produção).
- **Documentation URL** público — pode ser este repositório/doc publicado, ou uma página em
  `agencios`.
- **Privacy policy URL** público — ⚠️ **o agencios ainda NÃO tem** página de privacidade. É preciso
  publicar uma (coleta, uso, armazenamento, compartilhamento com terceiros, retenção, contato) antes
  de submeter. (Não há rota `/privacidade` hoje.)
- **Ícone** — usar `public/icon-512.png` (marca da agencios; ver [`brand-assets`]).
- **Conta de teste** com dados populados + instruções passo a passo para o revisor acessar de ponta a
  ponta (ex.: um workspace de demonstração com login/senha dedicados).
- **Screenshots em carrossel** (3–5 PNGs, ≥1000px de largura) **se** for submeter como *MCP App*.

---

## 3. Fluxo no portal (11 etapas)

1. **Introduction** — visão geral do impacto no diretório.
2. **Connection** — confirma server URL, transporte e modelo de conexão (URL única vs. por usuário).
3. **Tools** — sincroniza as tools automaticamente; aponta títulos/annotations faltando.
4. **Listing** — nome (≤100), tagline (≤55), descrição (≤2000), categorias, URLs, ícone, slug.
5. **Use cases** — casos de uso principais, pré-requisitos, escopo de leitura/escrita.
6. **Company** — nome, site, contato principal.
7. **Authentication** — OAuth, custom connection ou no auth.
8. **Data handling** — propriedade da API, dados sensíveis de saúde, conteúdo patrocinado.
9. **Test & launch** — instruções de acesso detalhadas + confirmação das credenciais de teste.
10. **Compliance** — sete reconhecimentos obrigatórios de política.
11. **Review** — leitura final antes de enviar.

Antes de submeter, valide o servidor com o **MCP Inspector** e como **conector personalizado** no
próprio Claude (rode cada tool de verdade).

---

## 4. Após submeter

Status e feedback do revisor aparecem no **submissions dashboard** do Admin settings. A listagem só
fica pública após aprovação.

---

## 5. Checklist rápido (antes de abrir o portal)

- [ ] Domínio de produção HTTPS, público, alcançável pelos IPs da Anthropic (`APP_HOST` setado).
- [ ] OAuth discovery acessível (`/.well-known/oauth-*`) **ou** decisão por *custom connection*.
- [ ] `initialize` + `tools/list` + `tools/call` funcionando (testado no MCP Inspector).
- [ ] Toda tool com `title` + `readOnlyHint`/`destructiveHint`; nomes ≤64; read/write separados.
- [ ] **Página de privacidade pública publicada** (pendente no agencios).
- [ ] Documentation URL público.
- [ ] Ícone (`public/icon-512.png`) e descrição/tagline/categorias prontos.
- [ ] Conta de teste populada + instruções para o revisor.

---

## Fontes
- [Submitting to the Connectors Directory — Claude docs](https://claude.com/docs/connectors/building/submission)
- [Pre-submission review criteria — Claude docs](https://claude.com/docs/connectors/building/review-criteria)
- [Remote MCP Server Submission Guide — Claude Help Center](https://support.claude.com/en/articles/12922490-remote-mcp-server-submission-guide)
- [Anthropic Connectors Directory FAQ — Claude Help Center](https://support.claude.com/en/articles/11596036-anthropic-connectors-directory-faq)
- [Building custom connectors via remote MCP servers — Claude Help Center](https://support.claude.com/en/articles/11503834-building-custom-connectors-via-remote-mcp-servers)
