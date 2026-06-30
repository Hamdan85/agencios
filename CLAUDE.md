# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **agencios** is the operating system of a social-media / creative agency. A user joins one or
> more **workspaces** (each workspace **is** an agency). A workspace owns **clients**, **projects**
> (each project belongs to a client), **tickets** (the unit of agency work, moving through a content
> production funnel), **meetings** (Google Calendar), and **billing** (the agency invoicing its
> clients via Mercado Pago). The platform itself is billed to the workspace via Stripe
> (subscription tiers + usage-based metering on creative generation).
>
> Read `docs/ARCHITECTURE.md` for the high-level map and `docs/SPECIFICATION.md` for the full,
> buildable specification. Per-network integration playbooks live in `docs/integrations/`.

## Language rules (CRITICAL — never violate)

**All code must be 100% in English.**
This includes: variable names, method names, class names, column names, enum keys,
constant names, symbol names, hash keys, file names, comments, and git messages.

**The only Portuguese allowed is user-facing strings rendered in the frontend UI.**
Examples of what IS allowed in Portuguese: JSX label text, button labels, placeholder
text, toast/flash messages rendered to the user, email body copy, WhatsApp/message copy sent to
clients, **URL path segments in the frontend React Router** (these are visible to the user in the
browser address bar — e.g. `/quadro`, `/projetos`, `/clientes`, `/calendario`, `/painel`).

Examples of what is NEVER allowed in Portuguese: column names (`agendado_em` → `scheduled_at`),
enum keys (`ideacao` → `ideation`, `concluido` → `done`), Ruby symbols (`:carrossel`),
JS object keys used as code (`{ carrossel: '...' }`), setting keys (`token_meta` → `meta_access_token`).

The ticket workflow statuses are user-facing in Portuguese but **coded in English**:
`ideation` → "Ideação", `scoping` → "Escopo", `production` → "Produção", `scheduled` → "Agendado",
`published` → "Postado / Monitorando", `retrospective` → "Retrospectiva / Lições aprendidas",
`done` → "Concluído". The translation layer is a frontend label map, never the enum key.

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
- AI: Anthropic Claude (summaries, captions, scope, retrospectives). Creative generation vendors:
  HeyGen + HyperFrames (video), **Google Banana** (Imagen 3 via Google AI API — carousels + images).

## Secrets

All secrets go in **Rails encrypted credentials only** (`rails credentials:edit`).
`.env` is for non-sensitive infrastructure config only (e.g. `DATABASE_URL`, `APP_HOST`, `REDIS_URL`).
Never put API keys, tokens, or passwords in `.env`.

`SystemConfig.app_host` reads `APP_HOST` env var, falls back to `http://localhost:3000`.

Per-workspace integration tokens (social OAuth, Mercado Pago) are stored **encrypted on database
models** (`SocialAccount`, `Setting`) via `encrypts`, NOT in credentials. App-level API keys
(Meta app secret, Stripe secret, HeyGen key, Anthropic key) go in credentials. See
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
URL segments (`/quadro`, `/calendario`, `/projetos`, `/clientes`, `/painel`). Never confuse the two.

The catch-all `get "*path", to: "spa#index"` serves the React SPA for all HTML GETs.

**Frontend route map (React Router, Portuguese segments):**
`/painel` (dashboard), `/quadro` (board), `/calendario` (calendar), `/tarefas` (my subtasks),
`/projetos` · `/projetos/:id`, `/clientes` · `/clientes/:id`, `/tickets/:id` · `/tickets/:id/:tab`
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

Sub-namespaces follow the domain entity:
`Operations::Tickets::*`, `Operations::Projects::*`, `Operations::Clients::*`,
`Operations::Creatives::*`, `Operations::Posts::*`, `Operations::Social::*`,
`Operations::Meetings::*`, `Operations::Billing::*`, `Operations::Invoices::*`, `Operations::Ai::*`.

- Base class: `Operations::Base`

### `app/services/vendors/` — Third-party API wrappers

Isolate all external API knowledge here. Each vendor has a `Client` class that wraps the SDK/HTTP
calls, and discrete `Actions::*` classes that delegate to the client. Each integration's exact
endpoints, scopes, and OAuth flow are documented in `docs/integrations/<vendor>.md`.

Current vendors: `Meta` (Instagram + Facebook), `TikTok`, `Youtube`, `Linkedin`, `X`,
`UploadPost` (aggregator fallback), `Heygen` + `Hyperframes` (video), an image generator,
`MercadoPago` (client billing), `Stripe` (SaaS billing), `Google` (Calendar/Meet), `Anthropic`.

```ruby
Vendors::Meta::Client.new(social_account).publish_media(...)   # low-level
Vendors::Meta::Actions::PublishMedia.call(...)                 # preferred call site
```

### `app/services/publishers/` — Cross-network publishing seam

`Publishers::SocialPublisher` is the single interface used by `Operations::Posts::Publish`.
It resolves, per network and per workspace, whether to publish **directly** (`Vendors::Meta`,
`Vendors::TikTok`, …) or via the **aggregator** (`Vendors::UploadPost`). A network is swapped
between direct and aggregator with a one-line route change here — callers never branch on provider.

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
`IdeaSynthesis`, `ScopeBuilder`, `CaptionWriter`, `CarouselCopy`, `Retrospective`,
`BestTimeToPost`. Base class: `Prompts::Base`.

### Calling convention summary

| Caller | Should call |
|---|---|
| Rails controller | `Controllers::*` |
| Sidekiq job | `Operations::*` |
| Webhook handler | `Controllers::Webhooks::*` → `Operations::*` |
| Operation needing external API | `Vendors::*::Actions::*` |
| Operation publishing a post | `Publishers::SocialPublisher` |
| Operation generating AI text | `Prompts::*` + `Vendors::Anthropic::*` |
| Operation generating a creative | `Operations::Creatives::*` + `Vendors::Heygen` (video) / `Vendors::Google::Banana` (image) |

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
`ideation → scoping → production → scheduled → published → retrospective → done`.
**All status transitions go through `Operations::Tickets::ChangeStatus`** (the single authoritative
point — records a `TicketStatusLog`, writes a history `Note`, refreshes the status-scoped AI
summary, and broadcasts to `ticket_<id>` + `board_<workspace_id>`). Never mutate `status` with a
bare `update!`. The **ticket view is contextual to its status** — each status renders its own field
set plus a Claude-generated summary (`ai_summaries` jsonb, keyed by status). See
`docs/SPECIFICATION.md` §"Contextual ticket view" for the per-status field map.

**Subtask** — `belongs_to :ticket`; optional `belongs_to :assignee` (User). `title`, `done`,
`due_date`, `position`. Subtasks assigned to a user are aggregated into that user's **My Tasks**
screen (`/tarefas`) across all tickets/workspaces.

**Creative** — `belongs_to :ticket`. A creative has a `creative_type` (registry key, acts as the
spec) and a `source`: `uploaded` or `generated`. Generatable types route to a generation pipeline:
`ugc_video` (HeyGen / HyperFrames), `carousel` (viral-pattern generator: brand identity, @handle,
user avatar, optional stock imagery), `image` (Google Banana / Imagen 3). Holds ActiveStorage attachments +
`metadata` jsonb.

**Generation** — `belongs_to :workspace, :user`; optional `belongs_to :creative`. `kind`:
`carousel` / `video` / `image`. `status`, `provider`, `cost_cents`, `metered_at`. **`carousel` and
`video` generations are the usage-based billing meters** — on completion `Operations::Billing::
RecordUsage` emits a Stripe meter event (idempotent on the generation id). Image generation is
tracked but (currently) not metered.

**SocialAccount** — `belongs_to :workspace`. `provider` enum (`instagram`, `facebook`, `tiktok`,
`youtube`, `linkedin`, `x`, `upload_post`). Encrypted OAuth tokens + external account ids. The
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
trial/cancellation state. Drives feature/seat gating + usage metering.

**Setting** — one per workspace (`belongs_to :workspace`). Brand identity (agency name, brand
voice/tone, default @handle, brand colors, logo, default creator avatar for UGC/carousels) +
encrypted credentials for Google Calendar (`google_access_token`, `google_refresh_token`) and
Mercado Pago (`mercadopago_access_token`, `mercadopago_user_id`). Social tokens live on
`SocialAccount`, not here.

## Adapters

**`SocialPublisher`** (`app/services/publishers/social_publisher.rb`) — the one way to publish a
`Post`. Routes per network to a direct vendor or the aggregator; reads tokens from `SocialAccount`.

**`AiAdapter`** (`app/adapters/ai_adapter.rb`) — wraps Anthropic for ticket summaries, idea
synthesis, scope building, caption writing, and retrospectives. Used by `SummarizeTicketJob`,
`GenerateCaptionsJob`, and the contextual ticket view.

## Frontend architecture

**Pages** in `app/frontend/pages/` (one dir per domain: `Board/`, `Calendar/`, `Tickets/`,
`Projects/`, `Clients/`, `Tasks/`, `Meetings/`, `Invoices/`, `Studio/`, `Settings/`, `Billing/`).
**Components** in `app/frontend/components/` (`board/`, `ticket/`, `creative/`, `layout/`, `ui/`).
**Hooks** in `app/frontend/hooks/` wrap TanStack Query: `useBoard`, `useTicket`, `useTickets`,
`useCalendar`, `useProjects`, `useClients`, `useSubtasks`, `useTicketChannel`, `useSettings`, etc.
**API** in `app/frontend/api/resources/` — thin axios wrappers. All paths are API paths
(`/tickets/:id`), never the React Router paths.

Real-time: hooks subscribe via `useTicketChannel` / `useBoardChannel`; events (`status_changed`,
`creative_ready`, `post_published`, `metric_updated`, `summary_ready`, `card_moved`) trigger
`queryClient.invalidateQueries`.

**The board** (`/quadro`): columns are the 7 statuses; cards are tickets; the project renders as a
colored chip on each card; cards drag between columns (a drop calls `POST /tickets/:id/advance` →
`Operations::Tickets::ChangeStatus`). Filters: project, client, assignee, channel, creative type.

**The calendar** (`/calendario`): shows scheduled posts (by `scheduled_at`) and meetings; supports
month/week views and drag-to-reschedule (updates the post / `ChangeStatus` as appropriate).

**Formatters** (`app/frontend/lib/formatters.js`): `dt()`, `shortDt()`, `date()`, `brl()`. Use
these — never pre-format dates/money on the backend.

## Serializers / frontend data

- Dates are serialized as ISO 8601 (`.iso8601`) — never pre-format in serializers
- Money is serialized in cents (integer); format with `brl()` on the frontend
- The frontend formatters handle all display

## AI pipeline flow

1. **Contextual ticket summary** — on status change (or explicit refresh),
   `Operations::Tickets::ChangeStatus` enqueues `SummarizeTicketJob` →
   `Operations::Ai::SummarizeTicket` → `Prompts::TicketSummary` (status-aware system prompt) →
   Claude → writes `ticket.ai_summaries[status]` and broadcasts `summary_ready` on `ticket_<id>`.
2. **Idea & scope** — in `ideation`/`scoping`, the lawyer-equivalent (the strategist) can ask
   Claude to synthesize the brief into ideas (`Prompts::IdeaSynthesis`) and turn an idea into a
   concrete scope + subtask checklist (`Prompts::ScopeBuilder` → creates subtasks via
   `Operations::Subtasks::Create`).
3. **Creative generation** — in `production`:
   - UGC video → `Operations::Creatives::GenerateUgcVideo` → `Vendors::Heygen` (or HyperFrames) →
     async render → webhook/poll → `Creative` finalized → `Generation` (`kind: video`) →
     `Operations::Billing::RecordUsage` meters it.
   - Carousel → `Operations::Creatives::GenerateCarousel` (brand identity + @handle + avatar +
     stock images + `Prompts::CarouselCopy`) → `Generation` (`kind: carousel`) → metered.
   - Image → `Operations::Creatives::GenerateImage` → `Generation` (`kind: image`, not metered).
4. **Captions** — `GenerateCaptionsJob` → `Prompts::CaptionWriter` produces per-network caption
   variants (length/hashtag rules per network).
5. **Publish & monitor** — in `scheduled`→`published`, `Posts::PublishJob` →
   `Operations::Posts::Publish` → `Publishers::SocialPublisher` → the network vendor. Then
   `Posts::SyncMetricsJob` (scheduled) → `Operations::Posts::SyncMetrics` writes `PostMetric`s.
6. **Retrospective** — entering `retrospective`, `Prompts::Retrospective` drafts a performance
   review from `PostMetric`s + the ticket history; the team edits and finalizes.

## Publishing pipeline

Direct integration is the default and preferred path (full control + deeper analytics); the
`upload_post` aggregator is a per-network fallback to ship fast. Each network's app creation, OAuth
scopes, publishing endpoints, and analytics endpoints are documented step-by-step in
`docs/integrations/`:
- `meta.md` (Instagram + Facebook — one Meta app), `tiktok.md`, `linkedin.md`,
  `x-twitter.md`, `upload-post.md` (aggregator), `google.md` (Sign-In, Calendar, YouTube,
  and Google Banana image generation), and `README.md` for the direct-vs-aggregator
  decision matrix.

Each guide maps every API call to a concrete `Vendors::<Network>::Actions::*` class and the
`SocialAccount` columns it reads — follow them exactly when implementing a vendor.

## Billing

Two **separate** money flows — never conflate them:

1. **SaaS billing (Stripe)** — agencios charges the **workspace**. A `Subscription` per workspace
   with one licensed item (plan/seats: `solo` 1 seat, `agencia` 5–20 seats, `enterprise` 20+) plus
   two **metered** items via Stripe Billing Meters: `carousel_generation` and `video_generation`.
   Usage is reported with `Vendors::Stripe::Actions::ReportMeterEvent` (idempotent identifier =
   `"#{generation.kind}:#{generation.id}"`). Legacy usage records are removed — use Meters. Details:
   `docs/integrations/stripe-billing.md`.
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
