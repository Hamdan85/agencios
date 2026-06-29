# Claude connector (remote MCP server + OAuth 2.1)

Lets a user **authorize Claude to operate their workspaces** (teams) through a
conversation. agencios exposes a remote **MCP server** at `/mcp` and an **OAuth
2.1** authorization server; the user adds it in Claude as a *custom connector*.

This is the standard primitive for "let Claude act on my SaaS". A "skill"
(SKILL.md) is **not** the access mechanism — the connector + OAuth flow is. A
complementary Agent Skill (teaching Claude the funnel) could be shipped later.

## How a user connects it

1. In Claude: **Settings → Connectors → Add custom connector**.
2. Paste the connector URL: `https://<your-host>/mcp` (shown, copyable, in
   agencios under **Configurações → Conexões**).
3. Claude discovers the OAuth server, **dynamically registers itself**
   (RFC 7591), and opens the consent page. The user logs into agencios (if not
   already) and approves.
4. Claude receives a token bound to the **user** and can now call the tools.

The token covers **all workspaces the user belongs to**; every workspace-scoped
tool takes a `workspace` argument (slug or id). Claude calls `list_workspaces`
first to learn the slugs.

Revoke access anytime under **Configurações → Conexões** (or `DELETE
/api/v1/connections/:application_id`).

## Endpoints

| Path | Purpose |
|---|---|
| `GET /.well-known/oauth-protected-resource` | RFC 9728 — points `/mcp` at this AS |
| `GET /.well-known/oauth-authorization-server` | RFC 8414 — endpoints + S256 PKCE + DCR |
| `POST /oauth/register` | RFC 7591 Dynamic Client Registration |
| `GET/POST /oauth/authorize`, `POST /oauth/token`, `/oauth/revoke`, `/oauth/introspect` | Doorkeeper (auth code + PKCE + refresh) |
| `POST /mcp` | MCP JSON-RPC (Streamable HTTP). `GET` → 405, `DELETE` → 204 |

A request to `/mcp` without a valid bearer token gets **401 +
`WWW-Authenticate: Bearer resource_metadata="…"`**, which is what triggers
Claude's OAuth flow.

## Architecture

- **MCP tools are a second transport into the existing `Controllers::*` service
  layer** — each tool builds `ActionController::Parameters` and calls the same
  service the JSON API uses, inheriting Pundit authorization + serializers. No
  business logic is duplicated (controllers-only-call-services holds: `/mcp` is
  just another controller).
- The tool catalogue is **declarative** in `app/services/mcp/registry.rb`;
  `Mcp::ToolBuilder` turns each spec into a `FastMcp::Tool` subclass (we use
  fast-mcp only for its Dry::Schema argument DSL + JSON-Schema generation — the
  transport is our own `Mcp::ServerController`, because fast-mcp 1.6 only speaks
  the deprecated 2024-11-05 SSE transport, not the Streamable HTTP + OAuth that
  Claude's connector needs).
- Per-call tenant context: `Mcp::ToolContext` resolves the workspace **only from
  the user's memberships** and populates `Current.{actor,workspace,membership}`.
- **Scopes** (`read`, `write`, `billing`) are a coarse capability grant on top of
  Pundit's per-role gate. A token can never exceed the user's own role, nor reach
  a workspace they're not in.
- Side-effecting / billable tool calls are written to `mcp_call_logs`
  (`Mcp::CallAudit`); reads are logged. Generation/publishing tools are flagged
  in their descriptions (real cost).
- Rate limiting (`config/initializers/rack_attack.rb`) covers `/oauth/register`,
  `/oauth/token`, and `/mcp`.

## Local end-to-end testing

```bash
# 1. Boot the app
bin/dev

# 2. Inspect the MCP endpoint (no token → 401 with WWW-Authenticate)
npx @modelcontextprotocol/inspector   # point it at http://localhost:3000/mcp

# 3. Mint a token in the console for a quick tools/call
bin/rails console
#   app  = Doorkeeper::Application.create!(name: "Inspector", redirect_uri: "https://localhost", scopes: "read write", confidential: false)
#   user = User.first
#   tok  = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: user.id, scopes: "read write", expires_in: 7200).token
#   → paste `Bearer <tok>` into Inspector, run list_workspaces / get_board

# 4. Real connector: expose a public URL, add it in Claude
cloudflared tunnel --url http://localhost:3000   # or: ngrok http 3000
#   → add https://<tunnel>/mcp in Claude → Settings → Connectors
```

Specs: `spec/requests/mcp/` (discovery, DCR, PKCE token exchange, 401 challenge,
tools/list, create+advance ticket, scope gate, tenant isolation, revoked token).
