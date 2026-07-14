# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **agencios** is the operating system of a social-media / creative agency. A user joins one or
> more **workspaces** (each workspace **is** an agency). A workspace owns **clients**, **projects**
> (each project belongs to a client), **tickets** (the unit of agency work, moving through a content
> production funnel), **meetings** (Google Calendar), and **billing** (the agency invoicing its
> clients via Mercado Pago). The platform itself is billed to the workspace via Stripe
> (subscription tiers + prepaid credits for video/image generation).
>
> Read `docs/ARCHITECTURE.md` for the high-level map and `docs/SPECIFICATION.md` for the full,
> buildable specification. Per-network integration playbooks live in `docs/integrations/`.

## Language rules (CRITICAL — never violate)

**All code must be 100% in English.**
This includes: variable names, method names, class names, column names, enum keys,
constant names, symbol names, hash keys, file names, comments, and git messages.

**The app is fully i18n (pt-BR default + en). User-facing copy lives ONLY in locale files —
hardcoded copy in code (Portuguese OR English) is a violation.**
- Frontend: `app/frontend/locales/<locale>/<namespace>.json` via i18next — components use
  `useTranslation('<ns>')` + `t('key')`; module-level label maps use access-time getters
  (see `lib/constants.js`). Guard: `node bin/check-i18n.mjs` (referenced keys + pt-BR/en parity).
- Backend: `config/locales/<surface>/{pt-BR,en}.yml` via `I18n.t`. The API request cycle runs
  inside `I18n.with_locale` (Localizable concern; user → workspace fallback; public portal
  resolves the CLIENT's locale). Jobs/mailers wrap explicitly (`with_recipient_locale`,
  `I18n.with_locale(user.locale)`) — never set `I18n.locale=`. Guard:
  `spec/i18n/hardcoded_copy_spec.rb`.
- **Never persist rendered copy** where a key column exists: system notes
  (`Notes::Create i18n_key:/i18n_params:` → `Note#display_body`), web push
  (`Push::Notify title_key:/body_key:` — rendered per-recipient), credit ledger
  (`description_key/description_params` → `display_description`).
- Locale model: `users.locale` (app UI, personal emails, push), `clients.locale` (portal,
  approval, invoices, report PDF), `clients.content_language` (the language AI-generated
  CONTENT is written in — captions/carousels/scripts follow the client's audience, not the UI),
  `workspaces.locale` (default for both + team-shared artifacts). AI prompts get the language
  via `Prompts::Base#response_language` / `#workspace_language` — never hardcode an output
  language in a prompt.
- **URL path segments in the React Router stay Portuguese** (canonical for all locales —
  e.g. `/quadro`, `/campanhas`, `/clientes`, `/calendario`, `/painel`).

Examples of what is NEVER allowed in Portuguese: column names (`agendado_em` → `scheduled_at`),
enum keys (`ideacao` → `ideation`, `concluido` → `done`), Ruby symbols (`:carrossel`),
JS object keys used as code (`{ carrossel: '...' }`), setting keys (`token_meta` → `meta_access_token`),
and i18n key names (`chave.criar` → `key.create`).

The ticket workflow statuses are **coded in English** with localized labels:
`ideation` → "Ideação"/"Ideation", `scoping` → "Escopo"/"Scoping", `production` → "Produção"/
"Production", `approval` → "Aprovação"/"Approval", `scheduled` → "Postagem"/"Posting",
`published` → "No ar"/"Live", `retrospective` → "Retrospectiva"/"Retrospective",
`done` → "Concluído"/"Done". The translation layer is the locale files (frontend
`common.json status.*`, backend `statuses.*`), never the enum key.

If a Portuguese identifier already exists in the codebase, create a rename migration /
refactor immediately — do not leave it.

## Development commands

```bash
# Start all processes (Rails + Vite + Sidekiq)
bin/dev   # or: foreman start -f Procfile.dev

# Individual processes
bin/rails server -p 3000
bin/vite dev
bundle exec sidekiq -C config/sidekiq.yml

# Database
bin/rails db:migrate
bin/rails db:rollback

# RSpec
bundle exec rspec                              # full suite
bundle exec rspec spec/models/ticket_spec.rb   # single file
bundle exec rspec spec/services/               # directory

# Rails console
bin/rails console

# Credentials (secrets)
EDITOR=nano bin/rails credentials:edit
```

## Stack

- Rails 8.1 + PostgreSQL (NOT SQLite). `pgvector` (`neighbor` gem) for any future semantic search.
- React 19 + React Router 7 + Vite + Tailwind CSS v4 — a **pure client-rendered SPA**
  served by `SpaController#index` (layout-less HTML shell + `application.jsx` entrypoint).
  The backend is a JSON API under `/api/v1/`. There is NO Inertia.
- Sidekiq for background jobs (queues: `critical`, `default`, `media`, `imports`, `low`).
  `sidekiq-cron` for scheduled work (token refresh, metric sync, invoice reconciliation).
- ActiveStorage on S3 for all media (creatives, assets, logos, avatars).
- ActionMailer — delivery `:test` in dev, `:smtp` in production via credentials.
- Action Cable (mounted at `/cable`) — real-time updates: `ticket_<id>`, `board_<workspace_id>`,
  `generations_<workspace_id>` channels.
- TanStack Query v5 for all frontend data fetching / caching.
- React Hook Form + Zod for forms. Radix UI primitives. `lucide-react` icons.
- `@dnd-kit` (or equivalent) for the drag-and-drop Kanban board.
- Tiptap for rich-text fields (briefs, scripts, captions, retrospectives).
- AI text: **OpenRouter** by default, **Anthropic** as selectable fallback — both behind the
  `Vendors::Ai` seam + `AiAdapter` facade (provider/models admin-editable in `AiConfig`; every
  call's cost logged to `AiUsageLog`). Creative generation: **OpenRouter video** (scene-based
  pipeline with Cartesia voice, Jamendo/Epidemic Sound music, FFmpeg compose), **OpenRouter image**
  (Gemini image model — carousels + images), **Pexels** stock imagery.

## Secrets

All secrets go in **Rails encrypted credentials only** (`rails credentials:edit`).
`.env` is for non-sensitive infrastructure config only (e.g. `DATABASE_URL`, `APP_HOST`, `REDIS_URL`).
Never put API keys, tokens, or passwords in `.env`.

`SystemConfig.app_host` reads `APP_HOST` env var, falls back to `http://localhost:3000`.

Per-workspace integration tokens (social OAuth, Mercado Pago) are stored **encrypted on database
models** (`SocialAccount`, `Setting`) via `encrypts`, NOT in credentials. App-level API keys
(Meta app secret, Stripe secret, OpenRouter/Anthropic keys) go in credentials. See
`docs/integrations/*` for the exact key per vendor.

## Database

- `schema.rb` is auto-generated — never edit it manually
- Always create a new migration to change the schema; never use `psql` directly
- Integer-backed enums for status fields; string columns use string-backed enums
- Every tenant-scoped table has a `workspace_id` (indexed, FK). Query through the workspace.

## Multi-tenancy

**`Workspace` is the tenant root.** A `User` belongs to many workspaces through `Membership`
(role: `owner`, `admin`, `manager`, `member`, `guest`). The active workspace is resolved per
request from the session and exposed via `Current` (`Current.workspace`, `Current.membership`,
`Current.user`). **Every domain query must be scoped to `Current.workspace`** — never load a
`Ticket`/`Project`/`Client` by bare id without the workspace scope.

`Membership#role` gates capability:
- `owner` — billing, delete workspace, everything
- `admin` — manage members, settings, integrations, everything operational
- `manager` — manage projects/tickets/clients/invoices, assign work
- `member` — work tickets assigned to them, create creatives, comment
- `guest` — read-only client-facing view of their own project(s) (approvals only)

Authorization is enforced with Pundit policies keyed on the membership role.

## Routing

Backend API routes all live under `/api/v1/` with **English** resource names
(`/api/v1/tickets`, `/api/v1/projects`, `/api/v1/board`). The React Router routes use **Portuguese**
URL segments (`/quadro`, `/calendario`, `/campanhas`, `/clientes`, `/painel`). Never confuse the two.

The catch-all `get "*path", to: "spa#index"` serves the React SPA for all HTML GETs.

**Frontend route map (React Router, Portuguese segments):**
`/painel` (dashboard), `/quadro` (board), `/calendario` (calendar), `/tarefas` (my subtasks),
`/campanhas` · `/campanhas/:id`, `/clientes` · `/clientes/:id`, `/tickets/:id` · `/tickets/:id/:tab`
(ticket detail — "ticket" is an accepted PT-BR product term), `/estudio` (creative studio),
`/reunioes` (meetings), `/cobrancas` (client invoices), `/configuracoes` (settings),
`/assinatura` (the workspace's own Stripe plan).

**When adding a new page:** add a backend API route under `/api/v1/`, a Portuguese frontend route
in `App.jsx`, and link with the Portuguese path.

## Service layer architecture

**Business logic lives exclusively in services. Controllers only call services.**

All service objects inherit from a base class that exposes `.call(...)` as a class method
(delegates to `new(...).call`). Never instantiate a service directly — always call `.call`.

### `app/services/controllers/` — HTTP-layer service objects

One class per controller action. Accept HTTP params + the current user/workspace; return a result
or raise. Mirror the controller namespace: `Tickets::Create`, `Tickets::Show`, `Board::Index`,
`Calendar::Index`, `Projects::Create`, `Creatives::Generate`, `Posts::Publish`, etc.

- No business logic here — delegate to `Operations::*` for anything non-trivial.
- May call `serialize` / `serialize_collection` helpers from `Controllers::Base`.
- Base class: `Controllers::Base`

### `app/services/operations/` — Domain operations

Called by Sidekiq jobs, webhooks, or other operations. No HTTP concerns. Own the side effects:
DB writes, emails, external API calls, broadcasts.

Sub-namespaces follow the domain:
`Operations::Tickets::*`, `Operations::Projects::*`, `Operations::Clients::*`,
`Operations::Creatives::*`, `Operations::Posts::*`, `Operations::Social::*`,
`Operations::Meetings::*`, `Operations::Billing::*`, `Operations::Invoices::*`,
`Operations::Ai::*`, `Operations::Video::*` (scene pipeline), `Operations::Autopilot::*`
(GO mode), `Operations::Strategy::*` (Estrategista chat), `Operations::Credits::*` (prepaid
wallet), `Operations::Approvals::*` (client approval portal), plus `Analytics`, `Attachments`,
`BrandAssets`, `Digests`, `Generations`, `Notes`, `Push`, `Reports`, `Scheduling`, `Subtasks`,
`Users`, `Workspaces`.

- Base class: `Operations::Base`

### `app/services/vendors/` — Third-party API wrappers

Isolate all external API knowledge here. Each vendor has a `Client` class that wraps the SDK/HTTP
calls, and discrete `Actions::*` classes that delegate to the client. Each integration's exact
endpoints, scopes, and OAuth flow are documented in `docs/integrations/<vendor>.md`.

Current vendors — social: `Meta` (Instagram + Facebook), `InstagramLogin`, `Threads`, `TikTok`,
`Youtube`, `Linkedin`, `X`. AI/media: `Ai` (the provider seam), `OpenRouter` (text + video + image),
`Anthropic`, `Cartesia` (voice), `Jamendo`/`EpidemicSound` behind
`Vendors::Music`, `Pexels` (stock), `Ffmpeg`. Money: `MercadoPago` (client billing), `Stripe`
(SaaS billing). Platform: `Google` (OAuth/Calendar), `WebPush`, `Posthog`, `Web` (URL reader),
`Render` (HTML render).

```ruby
Vendors::Meta::Client.new(social_account).publish_media(...)   # low-level
Vendors::Meta::Actions::PublishMedia.call(...)                 # preferred call site
```

### `app/services/publishers/` — Cross-network publishing seam

`Publishers::SocialPublisher` is the single interface used by `Operations::Posts::Publish`.
It resolves, per network and per workspace, the direct vendor to publish through (`Vendors::Meta`,
`Vendors::TikTok`, …). Every network integrates directly — callers never branch on provider.

### `app/services/creatives/` — Creative type specifications

Each creative type is a stateless class with two class methods (mirrors a template registry):
- `.type_key` — string key identifying the creative type (`reel`, `carousel`, `feed_image`,
  `story`, `ugc_video`, `ad`, `thumbnail`)
- `.spec` — the structural specification (dimensions, safe areas, copy limits, and, when the type
  is generatable, the prompt scaffold passed to the generation vendor)

Base class: `Creatives::Base`. Registry: `app/services/creatives.rb` maps type keys to classes.

### `app/services/prompts/` — AI prompt builders

Stateless value objects. Each exposes `#system` returning the system prompt string. Helpers read
from `Current.workspace` settings (agency name, brand voice).

Classes: `TicketSummary` (status-aware — produces the contextual summary per state),
`ScopeBuilder`, `FieldFill`, `CarouselCopy`, `Retrospective`, `StrategyPlanner`,
`VideoStoryboard`, `VideoEditor`, `VideoPromptImprover`, `ClientPositioning`,
`ClientFromLandingPage`, `ProjectAudit`. Base class: `Prompts::Base`.

### Calling convention summary

| Caller | Should call |
|---|---|
| Rails controller | `Controllers::*` |
| Sidekiq job | `Operations::*` |
| Webhook handler | `Controllers::Webhooks::*` → `Operations::*` |
| Operation needing external API | `Vendors::*::Actions::*` |
| Operation publishing a post | `Publishers::SocialPublisher` |
| Operation generating AI text | `Prompts::*` + `AiAdapter` (→ `Vendors::Ai` → OpenRouter \| Anthropic) |
| Operation generating a creative | `Operations::Creatives::*` (+ `Operations::Video::*` for video) / `Vendors::OpenRouter::Image` (image) |

Controllers must not contain business logic: no status transitions, no metric writes, no
side-effect orchestration. If it belongs in a service, create one.

## No model callbacks

Active Record lifecycle callbacks (`after_create`, `before_save`, `after_commit`, …) are
**forbidden** for side effects. Orchestrate every side effect (broadcasts, jobs, emails, external
calls, dependent records) explicitly in the service layer. Models hold associations, validations,
enums, scopes, and pure query/derivation methods only.

## Reuse services for entity creation

Never call `x.create!` for another entity from inside a service. Call that entity's own
operation/creator service. (E.g. `Operations::Tickets::Create` must not `Subtask.create!` directly —
it calls `Operations::Subtasks::Create`. A creative generated during production is created via
`Operations::Creatives::Create`/`Generate`, not a bare insert.)

## Key domain models

**Workspace** — the tenant (an agency). `has_many :memberships`, `:users` through them; `has_one
:setting`, `:subscription`; `has_many :clients, :projects, :tickets, :meetings, :invoices,
:social_accounts, :creatives, :posts, :generations`. `plan` is read from the subscription
(`solo` / `agencia` / `enterprise`); `seat_count` = `memberships.count`.

**Project** — `belongs_to :workspace, :client`. `has_many :tickets`. Carries a `color` used to
render the project chip/tag on board cards. `status`: `active` / `paused` / `archived`. A project
is the **tag** that groups tickets on the board; the board is filterable by project (among others).

**Ticket** — the central unit of agency work. `belongs_to :workspace, :project`; optional
`belongs_to :assignee` (User). `has_many :subtasks, :creatives, :posts, :notes,
:ticket_status_logs`. Linear `WORKFLOW` enum:
`ideation → scoping → production → approval → scheduled → published → retrospective → done`.
`Ticket::WORKFLOW` (not the enum integer) is the single source of truth for the funnel's ORDER —
`approval` was added later and is stored as `7`, so nothing may compare status integers.
**All status transitions go through `Operations::Tickets::ChangeStatus`** (the single authoritative
point — records a `TicketStatusLog`, writes a history `Note`, refreshes the status-scoped AI
summary, and broadcasts to `ticket_<id>` + `board_<workspace_id>`). Never mutate `status` with a
bare `update!`.

**Each column has exactly one action.** `production` = produce (upload/generate creatives);
`approval` = decide (approve / reject). Entering `approval` **is** the approval request
(`ChangeStatus` fires `Operations::Approvals::RequestApproval` — it never changes status itself), and
it is refused when there is no ready creative to approve. Full approval advances to `scheduled`
(`Operations::Approvals::OnFullyApproved`); a rejection bounces the ticket **back to `production`**
(`Operations::Approvals::RequestChanges`), carrying the client's feedback. A project may gate approval
internally (`require_client_approval` off): the ticket still stops in `approval`, but nobody is
emailed and it stays out of the client portal — the team approves it with `Approvals::ApproveAll`. The **ticket view is contextual to its status** — each status renders its own field
set plus a Claude-generated summary (`ai_summaries` jsonb, keyed by status). See
`docs/SPECIFICATION.md` §"Contextual ticket view" for the per-status field map.

**Subtask** — `belongs_to :ticket`; optional `belongs_to :assignee` (User). `title`, `done`,
`due_date`, `position`. Subtasks assigned to a user are aggregated into that user's **My Tasks**
screen (`/tarefas`) across all tickets/workspaces.

**Creative** — `belongs_to :ticket`. A creative has a `creative_type` (registry key, acts as the
spec) and a `source`: `uploaded` or `generated`. Generatable types route to a generation pipeline:
`ugc_video` (scene-based OpenRouter pipeline — see `Operations::Video::*` + `VideoScene`),
`carousel` (viral-pattern generator: brand identity, @handle, user avatar, optional stock
imagery), `image` (OpenRouter Gemini image model). Holds ActiveStorage attachments + `metadata` jsonb.

**Generation** — `belongs_to :workspace, :user`; optional `belongs_to :creative`. `kind`:
`carousel` / `video` / `image`. `status`, `provider`, `cost_cents`. **Customer billing is prepaid
credits**: `video` (cost-based estimate at request, trued-up at compose) and `image` (flat) debit
the wallet via `Operations::Credits::Debit`; `carousel` is included in the plan (0 credits).
`cost_cents` records the real vendor cost; the internal cost trail lives in `AiUsageLog`.

**SocialAccount** — `belongs_to :workspace`. `provider` enum (`instagram`, `facebook`, `threads`,
`tiktok`, `youtube`, `linkedin`, `x`). Encrypted OAuth tokens + external account ids. The
exact columns per provider are defined in `docs/integrations/<provider>.md`. Token refresh runs as
a scheduled Sidekiq job per provider.

**Post** — `belongs_to :ticket, :social_account`. A scheduled/published post on one network.
`status`: `scheduled` / `publishing` / `published` / `failed`. `scheduled_at`, `published_at`,
`external_post_id`, `permalink`, `caption`. `has_many :post_metrics`. Created in the `scheduled`
status, published in `published`/monitoring, analytics synced into `post_metrics`.

**PostMetric** — `belongs_to :post`. A dated snapshot of network analytics (`reach`, `views`,
`likes`, `comments`, `shares`, `saves`, plus a `raw` jsonb). Synced by `Posts::SyncMetricsJob`.

**Meeting** — `belongs_to :workspace`; optional `belongs_to :client, :project`. Google Calendar +
Meet. `google_event_id`, `meet_url`, `starts_at`, `ends_at`, `attendees` jsonb. Surfaced on the
calendar view alongside scheduled posts.

**Invoice** — `belongs_to :workspace, :client`. Linked to **zero or more** projects via
`invoice_projects` (an invoice may cover one project, several, or none). `status`: `draft` / `open`
/ `paid` / `overdue` / `canceled`. `has_many :charges`. Mercado Pago (Pix-first).

**Charge** — `belongs_to :invoice`. A single Mercado Pago payment attempt. `mp_payment_id`,
`method` (`pix` / `boleto` / `card`), `status`, Pix QR fields. Status is authoritative only after a
`GET /v1/payments/{id}` reconciliation — webhooks carry only the id.

**Subscription** — `belongs_to :workspace`. The agency's own SaaS plan. `plan`
(`solo` / `agencia` / `enterprise`), `stripe_customer_id`, `stripe_subscription_id`, seat quantity,
trial/cancellation state. Drives feature/seat gating; generation usage is charged from the
workspace's prepaid `CreditWallet` (see `Pricing` + `docs/pricing-model.md`).

**Setting** — one per workspace (`belongs_to :workspace`). Brand identity (agency name, brand
voice/tone, default @handle, brand colors, logo, default creator avatar for UGC/carousels) +
encrypted credentials for Google Calendar (`google_access_token`, `google_refresh_token`) and
Mercado Pago (`mercadopago_access_token`, `mercadopago_user_id`). Social tokens live on
`SocialAccount`, not here.

## Adapters

**`SocialPublisher`** (`app/services/publishers/social_publisher.rb`) — the one way to publish a
`Post`. Routes per network to its direct vendor; reads tokens from `SocialAccount`.

**`AiAdapter`** (`app/adapters/ai_adapter.rb`) — the provider-agnostic facade over the text-AI
layer: resolves the client + model per operation via `Vendors::Ai` (OpenRouter default, Anthropic
fallback; admin-editable in `AiConfig`), supports plain completion, forced-tool JSON output
(`complete_tool`) and web fetch, and logs every call to `AiUsageLog` via `Operations::Ai::LogUsage`.
Used by `Operations::Ai::*`, strategy/video chat, and the contextual ticket view.

## Frontend architecture

**Pages** in `app/frontend/pages/` (one dir per domain: `Tickets/` — the board/list hub with
`views/BoardView.jsx` + `views/ListView.jsx`, `Calendar/`, `Projects/`, `Clients/`, `Tasks/`,
`Meetings/`, `Posts/`, `Reports/`, `Studio/`, `Settings/`, `Billing/`, `Account/`, `Dashboard/`,
`Approval/` (public client portal), `Auth/`, `Errors/`). There is no `Board/` dir — `/quadro`
redirects into the tickets hub.
**Components** in `app/frontend/components/` (`board/`, `ticket/`, `creative/`, `layout/`, `ui/`,
plus `approval/`, `billing/`, `calendar/`, `client/`, `meeting/`, `posts/`, `project/`, `studio/`).
**`components/ui/` is the primitives library** — buttons, dialogs, sheets, badges (`Badge`/
`ColorBadge`), `IconTile`, `SectionLabel`, `MediaThumb`, `CopyButton`, feedback states (`Spinner`,
`InlineSpinner`, `Skeleton`, `EmptyState`, `PageLoader`), `PageHeader`/`StatCard`, filter bars,
entity selects, charts. **Always reuse a primitive before hand-rolling markup**; extend the
primitive (props/className) when a variant is needed.

**Viewing media — always the lightbox.** There is exactly ONE media viewer
(`components/ui/lightbox.jsx`), mounted once at the app root by `LightboxProvider` and opened
imperatively: `const { open } = useLightbox(); open(items, index)`. It is mobile-first (swipe,
pinch/double-tap zoom, drag-to-dismiss, tap-to-hide-chrome) and renders images, video, audio, PDFs
and a download card per slide. **Never** hand-roll an overlay, and never send a user to a raw asset
URL with `target="_blank"` — a blob URL outside the app is not a preview.
Build its items with the media layer in `lib/media.js` — `creativeToMedia(creative)` (a carousel is
ONE creative with several slides), `attachmentToMedia(att)`, `urlToMedia(url, opts)` — which is also
the only home for `isVideoUrl`/kind detection. Do not re-derive a creative's slides locally.
**Hooks** in `app/frontend/hooks/`: domain data hooks live under `hooks/data/*` and are re-exported
by `useData.js` (import from `@/hooks/useData`); `useBoard`/`useTicket` own the board/ticket-drawer
mutations; channel hooks (`useTicketChannel`, `useBoardChannel`, `useGenerationsChannel`,
`useStrategyChannel`) live in `useRealtime.js`; plus `useAuth`, `useSelection`, `useUrlState`,
`useInfiniteScroll`, `useOnlineStatus`, `useStrategy`.
**API** in `app/frontend/api/index.js` — thin axios `*Api` wrappers over `api/client.js`, query
keys in `api/queryKeys.js`. All paths are API paths (`/tickets/:id`), never React Router paths.

Real-time: hooks subscribe via `useTicketChannel` / `useBoardChannel`; events (`status_changed`,
`creative_ready`, `post_published`, `metric_updated`, `summary_ready`, `card_moved`) trigger
`queryClient.invalidateQueries`.

**The board** (`/tickets`, default view; `/quadro` redirects): columns are the 8 statuses; cards
are tickets; the project renders as a colored chip on each card; cards drag between columns (a
drop calls `POST /tickets/:id/advance` → `Operations::Tickets::ChangeStatus`). Filters: project,
client, assignee, channel, creative type.

**The calendar** (`/calendario`): shows scheduled posts (by `scheduled_at`) and meetings; supports
month/week views and drag-to-reschedule (updates the post / `ChangeStatus` as appropriate).

**Formatters** (`app/frontend/lib/formatters.js`): `dt()`, `shortDt()`, `date()`, `brl()`,
`num()`, `pct()`, `compact()`, `timeAgo()`, `relativeDay()` + the BR input masks. Use these —
never pre-format dates/money on the backend, never inline `toLocaleString`.

## Serializers / frontend data

- Dates are serialized as ISO 8601 (`.iso8601`) — never pre-format in serializers
- Money is serialized in cents (integer); format with `brl()` on the frontend
- The frontend formatters handle all display

## AI pipeline flow

1. **Contextual ticket summary** — on status change (or explicit refresh),
   `Operations::Tickets::ChangeStatus` enqueues `SummarizeTicketJob` →
   `Operations::Ai::SummarizeTicket` → `Prompts::TicketSummary` (status-aware system prompt) →
   Claude → writes `ticket.ai_summaries[status]` and broadcasts `summary_ready` on `ticket_<id>`.
2. **Fields & scope** — in `ideation`/`scoping`, "Gerar com IA" fills the status's fields
   (`Tickets::AiFillJob` → `Operations::Ai::FillFields` → `Prompts::FieldFill`) and builds the
   scope + subtask checklist (`Operations::Ai::BuildScope` → `Prompts::ScopeBuilder` → subtasks
   via `Operations::Subtasks::Create`). Project-level planning runs through the Estrategista chat
   (`Operations::Strategy::*` → `Prompts::StrategyPlanner`).
3. **Creative generation** — in `production` (each debits prepaid credits via
   `Operations::Credits::Debit`):
   - UGC video → `Operations::Creatives::GenerateUgcVideo` → scene pipeline
     (`Operations::Video::PlanScenes` → per-scene `RenderScene` via OpenRouter + Cartesia voice →
     `PollVideoSceneJob` → `Compose` with FFmpeg + music) → `Creative` finalized → credits
     trued-up to the real cost. Editable in the scene editor (chat + assets).
   - Carousel → `Operations::Creatives::GenerateViralCarousel` (brand identity + @handle + avatar
     + stock images + `Prompts::CarouselCopy`) → `Generation` (`kind: carousel`, 0 credits).
   - Image → `Operations::Creatives::GenerateImage` → `Vendors::OpenRouter::Image` →
     `Generation` (`kind: image`, 1 credit).
4. **Approval** — leaving `production` for `approval` sends the client the link
   (`Operations::Approvals::RequestApproval` → `ApprovalMailer` → the portal). **A human always
   decides to send it** — GO stops in `production` with the creatives ready and never asks the
   client on its own. The client approves or rejects per media slot (`Approvals::ApproveSlot` /
   `RequestChanges`); a rejection bounces the ticket back to `production` with the feedback and
   **regenerates nothing** — a regeneration spends credits, so only the team may trigger it. Full
   approval → `Approvals::OnFullyApproved` → `scheduled`, and there GO resumes: a ticket that ran
   on autopilot (`Ticket#autopilot_completed?`) gets its posts scheduled hands-off
   (`Approvals::AutoPublishApproved`), same as a project with `auto_publish_after_approval`.
5. **Publish & monitor** — in `scheduled`→`published`, `Posts::PublishJob` →
   `Operations::Posts::Publish` → `Publishers::SocialPublisher` → the network vendor. Then
   `Posts::SyncMetricsJob` (scheduled) → `Operations::Posts::SyncMetrics` writes `PostMetric`s.
6. **Retrospective** — entering `retrospective`, `DraftRetrospectiveJob` →
   `Operations::Ai::DraftRetrospective` (`Prompts::Retrospective`) drafts a performance review
   from `PostMetric`s + the ticket history; the team edits and finalizes.

## Publishing pipeline

Every network integrates directly (full control + deeper analytics). Each network's app creation,
OAuth scopes, publishing endpoints, and analytics endpoints are documented step-by-step in
`docs/integrations/`:
- `meta.md` (Instagram + Facebook — one Meta app), `tiktok.md`, `linkedin.md`,
  `x-twitter.md`, `google.md` (Sign-In, Calendar, YouTube,
  and Google Banana image generation), and `README.md` for the integration overview.

Each guide maps every API call to a concrete `Vendors::<Network>::Actions::*` class and the
`SocialAccount` columns it reads — follow them exactly when implementing a vendor.

## Billing

Two **separate** money flows — never conflate them:

1. **SaaS billing (Stripe)** — agencios charges the **workspace**. A `Subscription` per workspace
   with one licensed item (plan/seats: `solo` 1 seat, `agencia` 5–20 seats, `enterprise` 20+); no
   free tier — card-required 7-day trial; seats reconciled by `Operations::Billing::ReconcileSeats`.
   **Generation usage is prepaid credits**, not Stripe meters: video/image debit the workspace's
   `CreditWallet` (`Operations::Credits::*`, cost-plus pricing in `Pricing` — see
   `docs/pricing-model.md`); carousels are included in the plan. Credit packs are bought via Stripe
   checkout and granted by the webhook. `workspaces.godfathered` bypasses billing (admin-only,
   audited). Details: `docs/integrations/stripe-billing.md`.
2. **Client billing (Mercado Pago)** — the **agency** charges **its clients**. An `Invoice` →
   `Charge` (Pix-first; boleto/card too), reconciled via webhook + a scheduled sweep. Details:
   `docs/integrations/mercado-pago.md`.

## Internal admin

ActiveAdmin at `/admin`, restricted to platform staff (`User#staff?`). Manages: Workspaces,
Users, Memberships, Subscriptions (plan/seat overrides, comped access), Generations (usage audit +
manual credits), SocialAccounts (token health / expiry), Posts, Invoices, and feature flags.
Supports **impersonation** (`/admin/.../impersonate` → `/stop-impersonation`) for support. All
destructive/override actions are audit-logged. See `docs/ARCHITECTURE.md` §6.

## Conventions recap

- `.call(...)` on every service; never `new` a service directly.
- No AR callbacks for side effects — orchestrate in operations.
- Never create another entity with a bare `create!` inside a service — call that entity's service.
- Always scope queries to `Current.workspace`.
- Status changes only via `Operations::Tickets::ChangeStatus`.
- Publishing only via `Publishers::SocialPublisher`.
- Secrets: app keys in credentials; per-workspace tokens encrypted on models.
- Dates ISO 8601, money in cents — format on the frontend.
- Frontend: reuse `components/ui/` primitives and `lib/formatters.js` — never hand-roll
  pills/spinners/icon tiles/skeletons or inline `toLocaleString`.
- Viewing media only via `useLightbox()` + `lib/media.js` — never a hand-rolled overlay, never a
  `target="_blank"` to a raw asset URL.
