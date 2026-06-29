# agencios — Architecture

> The operating system of a social-media / creative agency. Modeled on the proven adv-os
> architecture (Rails 8.1 + React 19 SPA + service layer + Sidekiq + ActionCable), retargeted from
> the legal domain to agency content operations.
>
> This document is the high-level map. For the buildable, end-to-end specification (data model,
> migrations, endpoints, per-status field maps, generation pipelines, milestones) read
> [`SPECIFICATION.md`](./SPECIFICATION.md). For the working agreement read [`../CLAUDE.md`](../CLAUDE.md).
> For per-network integration playbooks read [`integrations/`](./integrations/).

Sections:
1. [Estrutura de arquitetura](#1-estrutura-de-arquitetura--architecture-structure)
2. [Stack](#2-stack)
3. [Principais especificações e regras](#3-principais-especificações-e-regras--key-specs--rules)
4. [Organização](#4-organização--code-organization)
5. [Funções do modelo de usuário](#5-funções-do-modelo-de-usuário--user-model-functions)
6. [Admin interno](#6-admin-interno--internal-admin)

---

## 1. Estrutura de arquitetura — Architecture structure

agencios is a **pure client-rendered React SPA on top of a JSON API**, with a strict service
layer, background workers, and real-time push. Nothing renders HTML server-side except the SPA
shell and a few public pages.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Browser — React 19 SPA (Vite, React Router 7, TanStack Query, Tailwind 4) │
│   Board (Kanban) · Calendar · Ticket detail (contextual) · Studio · …      │
└───────────────┬───────────────────────────────────────────┬──────────────┘
                │ JSON over HTTPS  (/api/v1/*)                │ WebSocket (/cable)
                ▼                                             ▼
┌──────────────────────────────────────┐      ┌─────────────────────────────┐
│  Rails 8.1 API                         │      │  Action Cable                │
│  Controllers (thin) → Controllers::*   │      │  ticket_<id>                 │
│  services → Operations::* (domain)     │◄────►│  board_<workspace_id>        │
│  → Vendors::* / Publishers::* / AI      │      │  generations_<workspace_id>  │
└───────┬───────────────┬───────────────┘      └─────────────────────────────┘
        │               │ enqueue
        ▼               ▼
┌──────────────┐  ┌──────────────────────────────────────────────────────────┐
│ PostgreSQL    │  │ Sidekiq (critical · default · media · imports · low)       │
│ (+ pgvector)  │  │  publish posts · generate creatives · sync metrics ·       │
│ ActiveStorage │  │  refresh tokens · summarize tickets · reconcile invoices    │
│ (S3)          │  └───────┬───────────────────────────────────────────────────┘
└──────────────┘          │ external APIs
                          ▼
   Meta (IG/FB) · TikTok · YouTube · LinkedIn · X · Upload-Post (aggregator)
   HeyGen / HyperFrames (video) · image model (carousels/images)
   Google Calendar/Meet · Mercado Pago (client billing) · Stripe (SaaS billing) · Anthropic
```

**Request lifecycle.** A browser request hits a thin Rails controller, which calls exactly one
`Controllers::*` service. That service authorizes (Pundit on the membership role), scopes to
`Current.workspace`, and either returns serialized data or delegates the real work to an
`Operations::*` service. Operations own all side effects and are the only things Sidekiq jobs and
webhook handlers call. Anything touching a third party goes through a `Vendors::*` wrapper;
anything publishing to a social network goes through the `Publishers::SocialPublisher` seam;
anything generating AI text goes through `Prompts::*` + `Vendors::Anthropic`.

**Tenancy.** `Workspace` is the tenant root. A `User` belongs to many workspaces via `Membership`.
The active workspace is resolved per request from the session into `Current` (`Current.workspace`,
`Current.membership`, `Current.user`). Every domain query is scoped to the workspace.

**The work funnel.** The domain is a content production pipeline. A `Ticket` (one unit of agency
work — a post, a campaign asset, a video) flows through seven ordered statuses, and the **ticket UI
is contextual to the current status**: each status shows its own field set plus a Claude-generated
summary. Tickets are visualized two ways — a **Kanban board** (columns = statuses, cards = tickets,
project as a colored tag) and a **calendar** (scheduled posts + meetings).

**Real-time.** Status changes, creative renders finishing, posts going live, metrics arriving, and
AI summaries completing are all pushed over Action Cable so the board, calendar, and ticket views
stay live without polling.

**Top-level layout** (mirrors adv-os):

```
app/
├── adapters/            # AiAdapter (Anthropic facade) + thin cross-cutting facades
├── channels/            # ApplicationCable + TicketChannel, BoardChannel, GenerationsChannel
├── controllers/
│   ├── api/v1/          # thin REST controllers (English resource names)
│   ├── auth/            # OAuth callbacks (Google, social networks, Mercado Pago, Stripe)
│   ├── webhooks/        # Stripe, Mercado Pago, Meta, TikTok, HeyGen, …
│   └── concerns/        # authentication (session + tenancy resolution)
├── frontend/            # React 19 SPA (pages, components, hooks, api, lib) — Portuguese routes
├── jobs/                # Sidekiq jobs → Operations::*
├── models/              # AR models (associations, enums, scopes, derivations — NO callbacks)
│   └── concerns/
├── serializers/         # ActiveModel::Serializer (ISO dates, money in cents)
└── services/
    ├── controllers/     # HTTP-layer service objects (one per action)
    ├── operations/      # domain operations (own all side effects)
    ├── vendors/         # third-party API wrappers (Client + Actions::*)
    ├── publishers/      # SocialPublisher (direct-vs-aggregator routing)
    ├── creatives/       # creative-type specs/registry (mirrors a template registry)
    └── prompts/         # AI prompt builders (status-aware ticket summary, captions, …)
config/                  # routes.rb, sidekiq.yml, schedule.yml (cron), cable.yml, credentials/
docs/                    # ARCHITECTURE.md, SPECIFICATION.md, integrations/*
```

---

## 2. Stack

| Layer | Choice | Notes |
|---|---|---|
| Web framework | **Rails 8.1** | JSON API under `/api/v1/`; SPA shell via `SpaController#index` |
| Database | **PostgreSQL** | `neighbor`/pgvector available for future semantic search |
| Frontend | **React 19 + React Router 7 + Vite** | pure CSR SPA, Portuguese URL segments |
| Data fetching | **TanStack Query v5** | all server state; invalidated by Action Cable events |
| Styling | **Tailwind CSS v4** + Radix UI + `lucide-react` | `class-variance-authority`, `tailwind-merge` |
| Board DnD | **@dnd-kit** | Kanban drag between status columns |
| Forms | **React Hook Form + Zod** | shared validation schemas |
| Rich text | **Tiptap** | briefs, scripts, captions, retrospectives |
| Real-time | **Action Cable** (`@rails/actioncable`) | `ticket_<id>`, `board_<workspace_id>`, `generations_<workspace_id>` |
| Background jobs | **Sidekiq 8 + sidekiq-cron** | queues: `critical, default, media, imports, low` |
| File storage | **ActiveStorage on S3** | all creatives/media; `image_processing`/`ruby-vips` |
| Auth | session cookie + `Session` token model + `has_secure_password`; Google OAuth | same pattern as adv-os |
| Authorization | **Pundit** | policies keyed on `Membership#role` |
| Serialization | **active_model_serializers** | ISO 8601 dates, money in cents |
| HTTP clients | **Faraday** (+retry) / **HTTParty**; **oj** | vendor wrappers |
| Pagination | **pagy** | |
| AI — text | **Anthropic Claude** | summaries, scope, captions, retrospectives |
| AI — video | **HeyGen** + **HyperFrames** | UGC / avatar talking-head; metered |
| AI — image/carousel | image model (e.g. Ideogram/Replicate/OpenAI images) | viral carousel generator + images; carousels metered |
| Social | Meta Graph (IG/FB), TikTok, YouTube, LinkedIn, X, Upload-Post | direct-first, aggregator fallback |
| Calendar | **Google Calendar/Meet** | `google-apis-calendar_v3`, `google-apis-meet_v2` |
| Client billing | **Mercado Pago** | Pix-first; boleto/card; webhooks |
| SaaS billing | **Stripe** | subscription tiers + Billing Meters (usage) |
| Admin | **ActiveAdmin** | platform staff console + impersonation |
| Observability | Sentry + PostHog (server & client) | feature flags via PostHog |
| Deploy | Kamal + Thruster + Puma | |

Frontend deps mirror adv-os: React 19, React Router 7, TanStack Query 5, Radix, Tailwind 4,
Tiptap, Zod + RHF, Stripe.js, Sentry, PostHog, ActionCable — plus `@dnd-kit` and a calendar lib
(`@fullcalendar/react` or a custom grid) for the two signature views.

---

## 3. Principais especificações e regras — Key specs & rules

**Language.** All code is English; only user-facing UI strings and frontend URL segments may be
Portuguese (see CLAUDE.md). Ticket statuses are coded in English and translated by a frontend label
map.

**The seven ticket statuses (linear `WORKFLOW`, integer enum):**

| # | enum key | UI label (PT) | The state means |
|---|---|---|---|
| 0 | `ideation` | Ideação | brief + objective + audience captured; idea being formed |
| 1 | `scoping` | Escopo | idea turned into concrete scope, creative type, channels, deliverables |
| 2 | `production` | Produção | creative being made/generated, copy + caption finalized, internal review |
| 3 | `scheduled` | Agendado | approved; channels + datetime set; queued to publish |
| 4 | `published` | Postado / Monitorando | live on the networks; analytics being collected |
| 5 | `retrospective` | Retrospectiva / Lições aprendidas | performance reviewed vs. goal; lessons logged |
| 6 | `done` | Concluído | archived with final metrics snapshot |

**Status transition rule (load-bearing).** Every transition goes through
`Operations::Tickets::ChangeStatus` — the single authoritative point. It records a
`TicketStatusLog`, writes a history `Note`, (re)generates the status-scoped AI summary, fires the
status's side effects (e.g. entering `published` triggers publishing; entering `retrospective`
drafts the retro), and broadcasts to `ticket_<id>` and `board_<workspace_id>`. Never write
`ticket.status = …; save`. A board drag-and-drop and a calendar reschedule both funnel here.

**Contextual ticket view.** The ticket detail screen renders a different field set per status, each
with a Claude summary at the top (`ticket.ai_summaries[status]`). The full per-status field map is
in [`SPECIFICATION.md`](./SPECIFICATION.md#contextual-ticket-view). Summary:
- *ideation* → brief, objective, target persona, references/mood, content pillar → AI: idea synthesis
- *scoping* → creative type, channels, copy brief, script, deliverables, due date → AI: scope + subtask checklist
- *production* → creative (uploaded or generated), caption, hashtags, approvals → AI: caption variants & QA vs. brief
- *scheduled* → channels + per-channel datetime, social accounts, first comment → AI: best-time + per-network adaptation
- *published* → live post links + rolling metrics → AI: performance summary vs. goal
- *retrospective* → outcome metrics, wins, improvements, repeat-recommendation → AI: auto-drafted retro
- *done* → read-only final snapshot → AI: case-study summary

**Board & calendar.** The board (`/quadro`) has one column per status, cards = tickets, the
**project shown as a colored tag** on the card, and is **filterable** (project, client, assignee,
channel, creative type). The calendar (`/calendario`) overlays scheduled posts and meetings, with
drag-to-reschedule. **Subtasks** of tickets are aggregated per user into the **My Tasks** screen
(`/tarefas`).

**Creatives.** A ticket's creative has a `creative_type` that *is* the spec (registry under
`app/services/creatives/`). Whenever a type is generatable, the system can produce it in-app:
- **UGC video** — HeyGen (avatar + script) or HyperFrames; async render → webhook/poll.
- **Carousel** — viral-pattern generator using brand identity, @handle, the user/creator avatar,
  and optional stock imagery + AI-written copy.
- **Image** — image model.
Every generation creates a `Generation` row; **carousel and video generations are the usage-based
billing meters**.

**Money flows are separate.** SaaS billing (Stripe) charges the workspace; client billing (Mercado
Pago) is the agency charging its clients. Never mix.

**Pricing.**
- *Subscription tiers (per workspace):* **Solo** (1 seat), **Agência** (5–20 seats), **Enterprise**
  (20+ seats). Seat count = `memberships.count`.
- *Usage-based (Stripe Billing Meters):* `carousel_generation` and `video_generation`, metered on
  completion, idempotent on the generation id.

**Non-negotiable code rules** (same spirit as adv-os): controllers are thin; all logic in services;
`.call` everywhere; no AR callbacks for side effects; never `create!` another entity inside a
service (call its service); always scope to `Current.workspace`; status only via `ChangeStatus`;
publishing only via `SocialPublisher`; app keys in credentials, per-workspace tokens encrypted on
models; dates ISO 8601, money in cents.

---

## 4. Organização — Code organization

The service layer is the heart of the system (identical layering to adv-os).

**`Controllers::*`** — one class per controller action; HTTP in, serialized data or raise out; no
business logic. Namespaced to mirror controllers: `Tickets::Create`, `Board::Index`,
`Calendar::Index`, `Creatives::Generate`, `Posts::Publish`, `Invoices::Create`, `Billing::*`,
`Webhooks::*`. Base: `Controllers::Base` (exposes `serialize` / `serialize_collection`).

**`Operations::*`** — domain operations; own every side effect; called by jobs, webhooks, other
operations. Sub-namespaces by entity: `Tickets`, `Subtasks`, `Projects`, `Clients`, `Creatives`,
`Posts`, `Social`, `Meetings`, `Invoices`, `Billing`, `Ai`. Base: `Operations::Base`. Canonical
ones: `Tickets::ChangeStatus`, `Tickets::Create`, `Tickets::SummarizeTicket`,
`Creatives::GenerateUgcVideo` / `GenerateCarousel` / `GenerateImage`, `Posts::Publish` /
`SyncMetrics`, `Social::ConnectAccount` / `RefreshToken`, `Meetings::SyncToCalendar`,
`Invoices::Create`, `Billing::RecordUsage` / `SyncSubscription`.

**`Vendors::*`** — third-party wrappers, one `Client` + `Actions::*` per vendor, all external
knowledge isolated here and documented in `docs/integrations/`. Vendors: `Meta`, `TikTok`,
`Youtube`, `Linkedin`, `X`, `UploadPost`, `Heygen`, `Hyperframes`, the image vendor, `MercadoPago`,
`Stripe`, `Google`, `Anthropic`.

**`Publishers::*`** — `SocialPublisher`, the single publish interface; routes each network to a
direct vendor or the aggregator per workspace config. Swapping a network's provider is a one-line
change here.

**`Creatives::*`** — creative-type spec classes (`.type_key`, `.spec`) + registry
(`app/services/creatives.rb`). Mirrors adv-os's `Petitions::*` registry.

**`Prompts::*`** — stateless AI prompt builders, each with `#system`: `TicketSummary` (status-aware),
`IdeaSynthesis`, `ScopeBuilder`, `CaptionWriter`, `CarouselCopy`, `Retrospective`, `BestTimeToPost`.

**Models** hold associations, enums, scopes, validations, and pure derivations only — never side
effects. **Jobs** are thin and delegate to `Operations::*`. **Serializers** emit ISO dates + cents.
**Channels** authorize via the session/workspace and `stream_from` the per-entity channel.

**Frontend** mirrors this on the client: `pages/` per domain, `components/{board,ticket,creative,
layout,ui}`, `hooks/` wrapping TanStack Query (+ `useTicketChannel`/`useBoardChannel` for live
updates), `api/resources/` thin axios wrappers, `lib/` (formatters, cable bridge, analytics facade).

**Calling convention** (who calls what): controller → `Controllers::*`; job → `Operations::*`;
webhook → `Controllers::Webhooks::*` → `Operations::*`; operation → `Vendors::*::Actions::*` /
`Publishers::SocialPublisher` / `Prompts::*`.

---

## 5. Funções do modelo de usuário — User model functions

A `User` is a person; their capabilities come from their `Membership` in the active workspace.
Authentication is session-based (`Session` token model + signed cookie + `has_secure_password`),
with Google OAuth for sign-in and Calendar.

**Roles (`Membership#role`, integer enum):**

| role | can |
|---|---|
| `owner` (0) | everything + billing + delete/transfer workspace; exactly one per workspace |
| `admin` (1) | manage members, settings, integrations; all operational actions |
| `manager` (2) | manage projects, tickets, clients, invoices; assign work; run generations |
| `member` (3) | work assigned tickets/subtasks, create & generate creatives, comment |
| `guest` (4) | read-only client view of their own project(s); approve/reject creatives only |

**`User` model — associations:** `has_many :memberships`, `:workspaces` through them, `:sessions`,
`:assigned_subtasks` (Subtask where assignee), `:assigned_tickets`, `:generations`,
`:created_creatives`; `has_one_attached :avatar`. Encrypted Google tokens (`google_access_token`,
`google_refresh_token`) for personal calendar.

**`User` model — methods (functions):**
- `default_workspace` → first membership's workspace (landing tenant)
- `workspaces` / `membership_for(workspace)` / `role_in(workspace)` → tenancy resolution
- `member_of?(workspace)` → boolean guard used by channels/policies
- `can_manage?(workspace)` → role ≥ `manager`
- `owner_of?(workspace)` / `admin_of?(workspace)` → privileged guards
- `display_name` → name or email fallback (used in serializers/avatars)
- `google_connected?` / `google_calendar_connected?` → integration state
- `assigned_open_subtasks` → feeds the My Tasks (`/tarefas`) screen across workspaces
- `staff?` → platform staff flag gating ActiveAdmin (`/admin`) and impersonation
- `billing_active?(workspace)` → delegates to `workspace.subscription.access_granted?`
- `generates_token_for :password_reset / :email_confirmation / :email_change` (Rails token gen)

**Workspace-side helpers** that complete the picture: `Workspace#seat_count`
(`memberships.count`, used by Stripe seat reconciliation), `#plan`, `#trialing?`,
`#billing_active?`, `#within_seat_limit?` (gate invites against the tier), `#owner`.

`Current` (`ActiveSupport::CurrentAttributes`) carries `session`, `workspace`, `membership` and
delegates `user` to the session — the single source of "who and where" for the request.

---

## 6. Admin interno — Internal admin

A platform-staff console (ActiveAdmin, gem `activeadmin`) mounted at `/admin`, authorized by
`User#staff?` (never a workspace role). It is for **operating the SaaS**, not for agencies to run
their day-to-day (that is the SPA).

**Resources & capabilities:**
- **Workspaces** — list/search, plan & status, seat usage, integration health; comp/extend access,
  toggle feature flags, force-cancel.
- **Users & Memberships** — find a user, see their workspaces/roles, reset auth state, manage
  staff flag; resend confirmations.
- **Subscriptions** — view Stripe linkage; override plan/seats, grant comped access, end trials;
  read-only invoice history.
- **Generations (usage audit)** — every `carousel`/`video`/`image` generation with cost, provider,
  and whether it was metered to Stripe; **grant manual usage credits** and re-drive a failed
  meter event.
- **SocialAccounts (integration health)** — per-workspace connected networks, token expiry, last
  successful publish/sync; flag accounts needing re-auth.
- **Posts & Invoices** — cross-workspace operational visibility for support; re-trigger a metric
  sync or a Mercado Pago reconciliation.
- **Feature flags** — surfaced from PostHog for staged rollout.

**Impersonation.** Staff can impersonate a workspace member to reproduce issues
(`/admin/users/:id/impersonate` → sets an impersonation session → `/stop-impersonation` restores).
Every impersonation and every override/credit/cancel is **audit-logged** (actor, target, action,
before/after) and surfaced read-only in the admin.

**Security.** Admin is gated by `staff?` + 2FA-eligible accounts only; it lives behind the same
authentication but a separate authorization path; destructive actions require confirmation and are
logged. It never bypasses tenant encryption (it cannot read decrypted client OAuth secrets — only
their presence/expiry).

---

*See [`SPECIFICATION.md`](./SPECIFICATION.md) for the concrete data model, migrations, API surface,
per-status field maps, generation/publishing pipelines, billing wiring, and the build milestones.*
