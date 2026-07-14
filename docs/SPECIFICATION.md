# agencios — System Specification

> **Audience:** Claude Code, building this system from scratch.
> **Goal:** an operating system for a social-media / creative agency — workspaces (agencies) running
> clients → projects → tickets through a content production funnel, with in-app creative generation,
> multi-network publishing + analytics, meetings, client invoicing, and SaaS billing.
>
> Read [`../CLAUDE.md`](../CLAUDE.md) (working agreement) and [`ARCHITECTURE.md`](./ARCHITECTURE.md)
> (high-level map) first. Per-network integration playbooks (exact endpoints, scopes, OAuth) are in
> [`integrations/`](./integrations/) — implement each vendor against its guide.
>
> Build in the milestone order in §12. Each milestone is independently shippable and testable.

---

## 0. Conventions (apply throughout)

- Rails 8.1 API + React 19 SPA. Layering and rules per CLAUDE.md (thin controllers; `.call`
  services; no AR callbacks; never `create!` another entity inside a service; scope every query to
  `Current.workspace`).
- Enums: integer-backed for status fields, string-backed for open vocabularies. Enum keys English.
- Money in **cents** (integer columns), serialized as integers, formatted with `brl()` on the front.
- Timestamps serialized as ISO 8601 (`.iso8601`).
- Encryption: `encrypts` on every token/secret column. App-level keys in Rails credentials.
- All tenant tables carry `workspace_id` (FK, indexed). Add composite indexes for the board/calendar
  queries (`[workspace_id, status]`, `[workspace_id, scheduled_at]`).
- RSpec for every model, operation, and request. Webmock all vendor HTTP.

---

## 1. Tenancy, users & auth

### Models

**Workspace** (the agency / tenant root)
```
name:string, slug:string (unique, format /\A[a-z0-9][a-z0-9-]{0,61}[a-z0-9]?\z/),
timezone:string (default "America/Sao_Paulo"), locale:string (default "pt-BR"),
brand_voice:text, default_handle:string, brand_primary_color:string, brand_secondary_color:string
```
- `has_many :memberships, :users (through), :clients, :projects, :tickets, :meetings, :invoices,
  :social_accounts, :creatives, :posts, :generations`; `has_one :setting, :subscription`
- `has_one_attached :logo`, `has_one_attached :default_creator_avatar`
- Methods: `seat_count` (= `memberships.count`), `plan` (= `subscription&.plan || :solo`),
  `trialing?`, `billing_active?`, `within_seat_limit?`, `owner`

**Membership** (User ↔ Workspace)
```
workspace_id, user_id, role:integer
enum role: { owner: 0, admin: 1, manager: 2, member: 3, guest: 4 }
```
- Unique `[workspace_id, user_id]`. Exactly one `owner` per workspace (validated).

**User**
```
email:string (unique, ci), password_digest, name:string, staff:boolean (default false),
google_uid:string, google_access_token:text (encrypted), google_refresh_token:text (encrypted),
google_calendar_connected_at:datetime, confirmed_at:datetime
```
- `has_secure_password validations: false`; `generates_token_for :password_reset (20m),
  :email_confirmation (24h), :email_change (24h)`
- `has_many :memberships, :workspaces (through), :sessions`; `has_one_attached :avatar`
- Methods per ARCHITECTURE §5 (`default_workspace`, `role_in`, `can_manage?`, `staff?`,
  `assigned_open_subtasks`, `display_name`, `google_connected?`).

**Session** (token auth — copy adv-os)
```
user_id, token:string (unique, random), workspace_id (active tenant), last_active_at, expires_at,
user_agent, ip_address
```

**Current** (`ActiveSupport::CurrentAttributes`)
```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :workspace, :membership
  delegate :user, to: :session, allow_nil: true
end
```

### Auth flow
- `Authentication` controller concern: `require_authentication` → `resume_session` (signed cookie
  `session_id` → `Session` → set `Current.session`) → `resolve_current_workspace` (from
  `session.workspace_id`, validated against membership; fallback first membership).
- Email/password registration + confirmation; password reset; Google OAuth sign-in
  (`omniauth-google-oauth2`).
- `POST /api/v1/session`, `DELETE /api/v1/session`, `POST /api/v1/registration`, password reset,
  email confirmation/change — same surface as adv-os.
- `Workspace switch`: `POST /api/v1/workspace/switch` updates `session.workspace_id`.
- **Invitations:** `Operations::Memberships::Invite` (email + role, seat-limit-gated) → email →
  `POST /api/v1/invitations/:token/accept`.

### Authorization
- Pundit policies keyed on `Current.membership.role`. A `WorkspaceScoped` policy concern enforces
  `record.workspace_id == Current.workspace.id`. Guests get read-only + approve/reject on their own
  projects' creatives only.

**Acceptance:** a user can sign up, create a workspace (becomes `owner`), invite members (blocked
past the tier seat limit), switch workspaces, and all data is workspace-isolated.

---

## 2. Clients & projects

**Client**
```
workspace_id, name:string, company:string, email:string, phone:string, document:string (CPF/CNPJ),
notes:text, status:integer  enum: { active: 0, archived: 1 }, attribution:jsonb
```
- `has_many :projects, :invoices, :meetings`

**Project**
```
workspace_id, client_id, name:string, description:text, color:string (hex, for board tag),
status:integer  enum: { active: 0, paused: 1, archived: 2 },
starts_on:date, ends_on:date, budget_cents:integer
```
- `has_many :tickets`; `has_many :invoice_projects`, `:invoices (through)`
- The **project is the tag** shown on board cards; `color` drives the chip color.

**Endpoints** (`/api/v1`): `resources :clients` (+ `:archive`), `resources :projects` (filter by
`client_id`, `status`). Controllers → `Controllers::Clients::*`, `Controllers::Projects::*`.

**Acceptance:** projects belong to a client; archiving a client cascades the UI to hide its
projects; a project's color renders on its tickets in the board.

---

## 3. Tickets — the core entity & the funnel

**Ticket**
```
workspace_id, project_id, assignee_id (User, nullable), created_by_id (User),
title:string, status:integer (default 0), priority:integer enum { low:0, medium:1, high:2 } default 1,
position:integer (ordering within a board column),
due_date:date, scheduled_at:datetime (target publish moment; drives calendar),
channels:string[] (target networks: instagram, facebook, tiktok, youtube, linkedin, x),
creative_type:string (registry key), ai_summaries:jsonb (default {}), fields:jsonb (default {}),
published_at:datetime, archived_at:datetime

enum status: { ideation:0, scoping:1, production:2, scheduled:3, published:4, retrospective:5, done:6,
               approval:7 }  # integers are storage; WORKFLOW below is the ORDER
WORKFLOW = %i[ideation scoping production approval scheduled published retrospective done].freeze
```
- `has_many :subtasks, :creatives, :posts, :notes, :ticket_status_logs`; `belongs_to :project,
  :workspace`; `belongs_to :assignee, optional`
- `fields` jsonb holds the status-specific structured data (see §4); `ai_summaries` holds the
  Claude summary per status keyed by status string.
- Methods (pure): `workflow_step`, `next_status`, `display_title` (title or `"#{creative_type} ·
  #{project.name}"`), `summary_for(status)`.
- **No `update!` on `status`** — only `Operations::Tickets::ChangeStatus`.

**TicketStatusLog** `ticket_id, from_status:integer, to_status:integer, user_id, created_at`

**Note** (ticket activity / history; Tiptap HTML or system text)
```
workspace_id, ticket_id, user_id (nullable for system notes), body:text, kind:integer
enum kind: { comment: 0, system: 1, ai: 2 }
```

**Subtask**
```
ticket_id, assignee_id (User, nullable), title:string, done:boolean default false,
due_date:date, position:integer
```

### `Operations::Tickets::ChangeStatus` (single authoritative transition)
Signature: `call(ticket, to_status, user:, force: false)`. Steps:
1. Guard non-regression unless `force` (board drag may move backward only for managers).
2. `ticket.update!(status: to_status)` (+ set `published_at` when entering `published`).
3. Create `TicketStatusLog`.
4. Create a `Note` (kind: `system`): "Status: <from> → <to>".
5. Enqueue `SummarizeTicketJob(ticket.id)` (regenerate the summary for the new status).
6. Fire status side effects:
   - entering `scheduled` → validate channels + `scheduled_at` present; ensure a `Post` per channel.
   - entering `published` → enqueue `Posts::PublishJob` for each scheduled `Post`.
   - entering `retrospective` → enqueue `DraftRetrospectiveJob`.
7. Broadcast `status_changed` to `ticket_<id>` and `card_moved` to `board_<workspace_id>`.

### Board & calendar endpoints
- `GET /api/v1/board?project_id&client_id&assignee_id&channel&creative_type` →
  `Controllers::Board::Index` returns columns keyed by status with serialized cards (id, title,
  project {name,color}, assignee {name,avatar}, channels, due_date, scheduled_at, counts of
  subtasks/creatives). Optimized: single query with includes, grouped by status.
- `POST /api/v1/tickets/:id/advance` body `{ to_status, position }` → `ChangeStatus` (+ reorder).
- `PATCH /api/v1/tickets/:id/reorder` for intra-column ordering.
- `GET /api/v1/calendar?from&to` → `Controllers::Calendar::Index` merges scheduled `Post`s (by
  `scheduled_at`) and `Meeting`s (by `starts_at`) into dated events.
- `resources :tickets` (index/show/create/update/destroy); nested `:subtasks`, `:creatives`,
  `:posts`, `:notes`.
- `GET /api/v1/tasks` (My Tasks) → all `Subtask`s assigned to `Current.user` across the workspace
  (and a `?scope=all_workspaces` variant), grouped by ticket/due date.

**Acceptance:** dragging a card on the board calls `advance`, persists the new status + position,
records a log + note, regenerates the summary, and the move appears live in another browser via
Action Cable. My Tasks lists my subtasks across tickets.

---

## 4. Contextual ticket view (per-status fields + AI summary)

The ticket detail screen is **status-driven**: it renders the field group for the current status,
shows the Claude summary on top, and offers the status's AI action. Structured values live in
`ticket.fields` (jsonb) namespaced by status; the summary in `ticket.ai_summaries[status]`.

> Implement the field groups as Zod schemas on the front + a permissive jsonb on the back. The
> backend validates only that keys belong to the current status group (a `Tickets::Fields` value
> object maps status → allowed keys).

| Status | Field group (`fields.<status>.*`) | AI summary & action (`Prompts::*`) |
|---|---|---|
| **ideation** | `brief` (rich), `objective`, `target_persona`, `references[]` (urls/uploads), `content_pillar`, `format_hypothesis` | `TicketSummary` synthesizes the idea; action: `IdeaSynthesis` → suggests angles/hooks |
| **scoping** | `creative_type` (sets `ticket.creative_type`), `channels[]` (sets `ticket.channels`), `copy_brief` (rich), `script` (rich), `deliverables[]`, `due_date`, `effort_estimate` | action: `ScopeBuilder` → produces a subtask checklist (creates `Subtask`s via `Operations::Subtasks::Create`) |
| **production** | `creative_id` (selected/active creative), `caption` (rich), `hashtags[]`, `production_scope` | the stage's action is **producing** the creatives (upload / generate); `CaptionWriter` → caption variants; carousel copy via `CarouselCopy` |
| **approval** | none — the stage IS the decision, taken on the creatives (`Creative#approval_state` `{pending, approved, changes_requested, not_selected}`) | the stage's action is **approve / reject**, per media slot. Entering it requests the client's approval; rejection returns the ticket to **production**, full approval advances it to **scheduled** |
| **scheduled** | `scheduled_at` (sets `ticket.scheduled_at`), per-channel `schedule[]` `{network, social_account_id, datetime}`, `first_comment`, `link_in_bio`, `auto_publish:boolean` | action: `BestTimeToPost` → suggests slots; per-network caption adaptation summary |
| **published** | (read-only, hydrated) `posts[]` with `permalink`, live `metrics` (reach/views/likes/comments/shares/saves), `monitor_alerts[]` | `TicketSummary` → performance vs. `objective` so far |
| **retrospective** | `outcome_metrics` (final snapshot), `wins[]`, `improvements[]`, `repeat_recommendation` enum `{repeat, iterate, retire}`, `lessons_learned` (rich) | action: `Retrospective` → drafts the whole retro from metrics + history; team edits |
| **done** | read-only archive: final metric snapshot + links to deliverables | `TicketSummary` → short case-study blurb |

`SummarizeTicketJob` → `Operations::Ai::SummarizeTicket(ticket, status)` builds the
`Prompts::TicketSummary` system prompt (status-aware, includes the relevant `fields` + recent notes
+ metrics when published), calls `Vendors::Anthropic`, writes `ai_summaries[status]`, broadcasts
`summary_ready`.

**Acceptance:** changing status swaps the rendered field group; the AI summary regenerates and
streams in; the `scoping` AI action creates real subtasks; `published` shows live metrics.

---

## 5. Creatives & in-app generation

**Creative**
```
workspace_id, ticket_id, creative_type:string (registry key),
source:integer enum { uploaded: 0, generated: 1 },
status:integer enum { draft: 0, generating: 1, ready: 2, failed: 3 },
provider:string (heygen|hyperframes|<image_vendor>|null), metadata:jsonb,
caption:text, version:integer default 1, parent_id (for versions)
```
- `has_many_attached :assets` (final media); `belongs_to :ticket`; `has_one :generation`

**Creative-type registry** (`app/services/creatives/`, base `Creatives::Base`, registry
`app/services/creatives.rb`). Each type: `.type_key` + `.spec` (dimensions, safe areas, copy limits,
generation prompt scaffold). Types: `reel`, `feed_image`, `carousel`, `story`, `ugc_video`, `ad`,
`thumbnail`, `cover`.

**Generation**
```
workspace_id, user_id, creative_id (nullable), kind:integer enum { carousel:0, video:1, image:2 },
status:integer enum { queued:0, processing:1, completed:2, failed:3 },
provider:string, external_id:string, cost_cents:integer,
params:jsonb, result:jsonb, failure_reason:string
```

### Generation pipelines

**UGC video** — `Operations::Creatives::GenerateUgcVideo(ticket:, avatar:, voice:, script:,
provider: :heygen)`:
1. Create `Creative(source: generated, status: generating, creative_type: ugc_video)` +
   `Generation(kind: video, status: queued, provider:)`.
2. `Vendors::Heygen::Actions::GenerateVideo` (or HyperFrames) → store `external_id`; status
   `processing`; enqueue `PollHeygenVideoJob` (safety net).
3. On webhook (`Controllers::Webhooks::Heygen`, signature-verified) or poll completion →
   `Operations::Creatives::FinalizeGeneration`: download MP4 → attach to `Creative` → `ready`;
   set `Generation.completed`, compute the real `cost_cents`, and true-up the prepaid credit
   debit (`Operations::Credits::Debit`, cost-plus via `Pricing.credits_for`). Broadcast
   `creative_ready`.
See `integrations/heygen.md`.

**Carousel** — `Operations::Creatives::GenerateCarousel(ticket:, slides:, options:)`:
- Viral-pattern generator. Inputs assembled from: workspace **brand identity** (logo, colors,
  `default_handle`), the **@handle**, the **creator avatar** (`workspace.default_creator_avatar` or
  per-creative override), optional **stock images** (a stock-image vendor search), and AI copy via
  `Prompts::CarouselCopy` (hook slide → value slides → CTA slide).
- Render each slide (HTML→image or image-model composition) → attach as `assets` → `Generation
  (kind: carousel)`. Carousels are **included in the plan** (0 credits — no wallet debit).

**Image** — `Operations::Creatives::GenerateImage(ticket:, prompt:, ref_images:)`:
- Image model → attach → `Generation(kind: image)`; debits the prepaid `CreditWallet` (1 credit)
  via `Operations::Credits::Debit`.

**Uploaded creatives** — `Operations::Creatives::Create` with direct ActiveStorage upload (no
generation row).

**Endpoints:** `resources :creatives` nested under tickets; `POST /api/v1/tickets/:id/creatives/
generate` body `{ kind, type, params }` → `Controllers::Creatives::Generate`. A workspace-level
**Studio** (`/estudio`) lists generators + brand assets and can generate standalone creatives.

**Acceptance:** generating a UGC video creates `Generation(kind: video)`, renders async, finalizes
on webhook, attaches the MP4, and debits the prepaid `CreditWallet` exactly once (cost-based
estimate at request, trued-up to the real cost on finalize). Carousel generation produces N slide
images using brand identity + handle + avatar (0 credits — included in the plan).

---

## 6. Social accounts, publishing & analytics

**SocialAccount** (one row per connected network per workspace)
```
workspace_id, provider:integer enum { instagram:0, facebook:1, tiktok:2, youtube:3, linkedin:4, x:5, threads:7 },
external_user_id:string, username:string, page_id:string, ig_user_id:string, channel_id:string,
member_urn:string, default_org_urn:string,            # provider-specific ids (see each guide)
user_access_token:text (encrypted), page_access_token:text (encrypted), refresh_token:text (encrypted),
token_expires_at:datetime, scopes:jsonb, status:integer enum { connected:0, needs_reauth:1, revoked:2 },
last_synced_at:datetime
```
> Add provider-specific columns exactly as each `integrations/<provider>.md` specifies. Encrypt
> every token column.

**Post** (a scheduled/published post on one network)
```
workspace_id, ticket_id, social_account_id, status:integer enum { scheduled:0, publishing:1, published:2, failed:3 },
scheduled_at:datetime, published_at:datetime, caption:text, external_post_id:string, permalink:string,
media:jsonb (asset refs), failure_reason:string
```
- `has_many :post_metrics`

**PostMetric** `post_id, captured_at, reach:integer, views:integer, likes:integer, comments:integer,
shares:integer, saves:integer, raw:jsonb`

### Publishing seam
`Publishers::SocialPublisher.publish(post)` resolves the provider for `post.social_account` and
calls the right direct vendor action. Every network integrates directly. Implement each vendor
strictly per its guide.

`Operations::Posts::Publish(post)`:
1. status → `publishing`; broadcast.
2. `Publishers::SocialPublisher.publish(post)` → vendor create→publish (handle async container/
   render polling per network; Reels/video need status polling — see `instagram.md`/`facebook.md`/
   `tiktok.md`/`youtube.md`).
3. On success: store `external_post_id`, `permalink`, `published_at`; status `published`; broadcast
   `post_published`. On failure: status `failed`, `failure_reason`; create a `Note(kind: system)`;
   broadcast.

`Operations::Posts::SyncMetrics(post)` → vendor insights action → upsert a dated `PostMetric`.
Scheduled `Posts::SyncMetricsJob` runs for posts published in the last N days (denser early, then
daily), driven by `sidekiq-cron`.

### Connect flow
`/configuracoes` → "Conectar rede" → OAuth per network (`auth/<network>` authorize → callback →
`Operations::Social::ConnectAccount` persists `SocialAccount`). Token refresh: per-provider
`Social::RefreshTokenJob` (cron) re-exchanges before `token_expires_at` and sets `needs_reauth` on
failure.

**Endpoints:** `resources :social_accounts` (index/destroy + `:reconnect`); `auth/:provider`,
`auth/:provider/callback`; webhooks per provider under `/webhooks/*`.

**Acceptance:** a workspace connects Instagram; a ticket in `scheduled` with channel `instagram`
creates a `Post`; entering `published` publishes it (container→publish, polling Reels) and stores
the permalink; `SyncMetrics` populates `PostMetric`s shown on the ticket's `published` view.

---

## 7. Meetings (Google Calendar)

**Meeting** `workspace_id, client_id (nullable), project_id (nullable), title, starts_at, ends_at,
google_event_id, meet_url, attendees:jsonb, notes:text`

- `Operations::Meetings::SyncToCalendar` creates/updates the Google Calendar event (+ Meet link)
  via `Vendors::Google::Calendar`; `RemoveFromCalendar` on delete.
- Uses the connecting user's encrypted Google tokens; workspace timezone for slotting.
- Surfaced on `/calendario` alongside scheduled posts and on `/reunioes`.
- Endpoints: `resources :meetings`. (Optional later: Calendly-style booking links.)

**Acceptance:** creating a meeting creates a Google Calendar event with a Meet link and shows on
the calendar next to scheduled posts.

---

## 8. Client billing (Mercado Pago)

**Invoice** `workspace_id, client_id, status:integer enum { draft:0, open:1, paid:2, overdue:3,
canceled:4 }, amount_cents:integer, currency:string default "BRL", description:text, due_date:date,
external_reference:string (unique)`
- `has_many :invoice_projects`, `:projects (through)` (an invoice covers 0..N projects),
  `has_many :charges`

**InvoiceProject** `invoice_id, project_id` (join)

**Charge** `invoice_id, mp_payment_id:string (unique), method:integer enum { pix:0, boleto:1,
card:2 }, status:string, amount_cents, pix_qr_code:text, pix_qr_code_base64:text, ticket_url:string,
expires_at:datetime`

- `Operations::Invoices::Create` builds the invoice (+ optional project links) and a `Charge`
  (Pix-first) via `Vendors::MercadoPago::Actions::CreatePayment`, persisting the QR fields.
- `Controllers::Webhooks::MercadoPago` verifies the `x-signature` HMAC, enqueues
  `SyncMercadoPagoPaymentJob` → `Operations::Billing::SyncPaymentStatus` (which always does
  `GET /v1/payments/{id}` — never trusts the webhook body — and moves the invoice forward only).
- A scheduled reconciliation sweep catches Pix payments that arrive without a prompt webhook.
- Multi-tenant later: each workspace connects its own Mercado Pago via OAuth (split payments).
See `integrations/mercado-pago.md`.

**Endpoints:** `resources :invoices` (+ `:send`, `:cancel`); `POST /webhooks/mercadopago`.
Frontend `/cobrancas`.

**Acceptance:** creating an invoice for a client (optionally tagged to projects) returns a Pix QR;
paying it (sandbox) flips the invoice to `paid` via webhook + reconciliation.

---

## 9. SaaS billing (Stripe — subscription seats + prepaid credits)

**Subscription** `workspace_id, plan:integer enum { solo:0, agencia:1, enterprise:2 },
stripe_customer_id, stripe_subscription_id, status:string, seats:integer, trial_ends_at:datetime,
current_period_end:datetime, cancel_at:datetime`

- Methods: `access_granted?`, `trialing?`, `seat_limit` (solo 1, agencia 5–20, enterprise 20+).
- **One Stripe subscription per workspace** with exactly **one licensed item** — the plan/seats
  (has `quantity`). There are **no metered items / no Billing Meters**. Generation usage is billed
  from the workspace's prepaid `CreditWallet`, not through Stripe.

Wiring (see `integrations/stripe-billing.md`):
- `Vendors::Stripe::Actions::CreateCheckoutSession` — subscription Checkout with the single licensed
  plan price (adjustable quantity for Agência 5–20).
- `Vendors::Stripe::Actions::CreateCreditCheckoutSession` — a **one-time** Checkout for a credit
  pack, using inline `price_data` (no pre-created Stripe Price). The webhook grants the credits to
  the wallet.
- `Vendors::Stripe::Actions::CreatePortalSession` — billing portal.
- **Plan prices** are the DB `PricingPlan.price_cents` (source of truth); saving a plan in `/admin`
  pushes it to Stripe as a recurring Price via `Operations::Billing::SyncPlanToStripe`.
- **Generation usage** debits the prepaid `CreditWallet` via `Operations::Credits::Debit`
  (cost-plus via `Pricing.credits_for`): video (cost-based estimate, trued-up at compose) and image
  (flat) debit credits; carousel is included in the plan (0 credits).
- `Operations::Billing::SyncSubscription` — from `Controllers::Webhooks::Stripe`
  (`checkout.session.completed`, `customer.subscription.*`, `invoice.paid`,
  `invoice.payment_failed`).
- `ReconcileSeatsJob` (cron) keeps the licensed `quantity` == `workspace.seat_count`.

**Endpoints:** `resource :billing` (`show`, `checkout_session`, `portal`, `change_plan`, `cancel`,
`reactivate`) + credit-pack checkout; `POST /webhooks/stripe`. Frontend `/assinatura`.

**Gating:** `member` invites blocked past `seat_limit`; generation blocked if `!access_granted?`
or the wallet lacks credits. Jobs short-circuit on inactive billing.

**Acceptance:** a workspace subscribes to Agência (8 seats); a video generation debits the prepaid
credit wallet once (trued-up to real cost on finalize), a carousel debits nothing, and a completed
generation is never double-charged.

---

## 10. Real-time, jobs & scheduling

**Channels** (authorize via session + workspace membership):
- `TicketChannel` → `ticket_<id>`: `status_changed`, `summary_ready`, `creative_ready`,
  `post_published`, `metric_updated`, `note_added`.
- `BoardChannel` → `board_<workspace_id>`: `card_moved`, `ticket_created`, `ticket_updated`.
- `GenerationsChannel` → `generations_<workspace_id>`: `generation_progress`, `generation_done`.

**Sidekiq queues:** `critical` (webhooks, publishing, payments), `default` (tickets, summaries),
`media` (creative generation, downloads, metric sync), `imports` (bulk pulls), `low` (cleanup).

**Cron (`sidekiq-cron`):** `Posts::SyncMetricsJob` (multiple times/day), per-provider
`Social::RefreshTokenJob`, `ReconcileSeatsJob` (daily), `Invoices::ReconcileJob` (Mercado Pago
sweep), `PurgeExpiredSessionsJob` (weekly), `MonitorScheduledPostsJob` (publish due posts /
escalate failures).

**ApplicationJob:** `retry_on` transient vendor errors (rate limit/overload) with backoff;
`discard_on` permanent (auth/billing) errors; `skip_inactive?(workspace)` billing gate.

---

## 11. Frontend (React 19 SPA)

**Pages** (`app/frontend/pages/`, Portuguese routes):
- `Board/` → `/quadro` — Kanban (`@dnd-kit`), 7 columns, project-color chips, filter bar (project,
  client, assignee, channel, creative type). Drag → `tickets.advance`.
- `Calendar/` → `/calendario` — month/week, scheduled posts + meetings, drag-to-reschedule.
- `Tickets/Show` → `/tickets/:id/:tab` — **contextual** layout: status stepper, AI summary card,
  the current status's field group (Zod-validated), creatives panel, posts/metrics panel, subtasks,
  activity/notes. The visible field group + AI action switch by status (§4).
- `Tasks/` → `/tarefas` — My Tasks: my subtasks across tickets, grouped by due date.
- `Projects/`, `Clients/` → `/projetos`, `/clientes`.
- `Studio/` → `/estudio` — creative generators (UGC video, carousel, image) + brand assets.
- `Meetings/` → `/reunioes`. `Invoices/` → `/cobrancas`. `Settings/` → `/configuracoes`
  (team, integrations/social connect, brand identity, Google, Mercado Pago). `Billing/` →
  `/assinatura`. `Dashboard/` → `/painel`.

**Hooks** wrap TanStack Query: `useBoard`, `useTicket`, `useTickets`, `useCalendar`, `useProjects`,
`useClients`, `useSubtasks`, `useCreatives`, `useSocialAccounts`, `useInvoices`, `useBilling`,
`useSettings`, plus `useTicketChannel`/`useBoardChannel`/`useGenerationsChannel` (Action Cable →
`invalidateQueries`).

**API resources** (`api/resources/*`): thin axios wrappers on the API paths. **lib/**: `formatters`
(`dt`, `shortDt`, `date`, `brl`), `cable` bridge, analytics facade (`lib/analytics/` with `maskPath`
mirroring the route table — same discipline as adv-os).

---

## 12. Build milestones (implement in order)

1. **Foundation & tenancy** — Rails 8.1 API + Vite SPA skeleton, `User`/`Session`/`Workspace`/
   `Membership`/`Current`, auth (email + Google), invitations, workspace switch, Pundit, SPA shell
   + layout + sidebar. *Ship:* sign up → workspace → invite → switch, all isolated.
2. **Clients & projects** — CRUD + serializers + pages. *Ship:* projects under clients with colors.
3. **Tickets, board & status engine** — `Ticket`/`Subtask`/`Note`/`TicketStatusLog`,
   `Operations::Tickets::ChangeStatus`, board endpoint + Kanban DnD, My Tasks, `TicketChannel`/
   `BoardChannel`. *Ship:* live drag-between-columns board with subtasks.
4. **Contextual ticket view + AI summaries** — per-status field groups, `Prompts::TicketSummary`
   + `IdeaSynthesis`/`ScopeBuilder`, `SummarizeTicketJob`, `Vendors::Anthropic`. *Ship:* status-aware
   ticket UI with streaming Claude summaries; scoping creates subtasks.
5. **Creatives & generation** — registry, `Creative`/`Generation`, UGC video (HeyGen) + carousel +
   image pipelines, Studio, `GenerationsChannel`. *Ship:* generate a UGC video + a branded carousel
   on a ticket.
6. **Social connect, publishing & analytics** — `SocialAccount`/`Post`/`PostMetric`,
   `Publishers::SocialPublisher`, per-network vendors (start Instagram + Facebook), connect OAuth,
   publish on entering `published`, `SyncMetrics`. *Ship:* schedule → publish to IG/FB → see metrics.
7. **Calendar & meetings** — calendar view, `Meeting` + Google Calendar/Meet. *Ship:* unified
   calendar of posts + meetings.
8. **SaaS billing (Stripe)** — `Subscription`, seat Checkout, prepaid credit packs (one-time
   Checkout), `CreditWallet`/`Operations::Credits::*`, plan-price sync, webhooks, seat
   reconciliation, gating. *Ship:* paid seat plans + prepaid video/image credits.
9. **Client billing (Mercado Pago)** — `Invoice`/`Charge`, Pix, webhooks + reconciliation. *Ship:*
   invoice a client, get paid via Pix.
10. **Remaining networks** — Threads, TikTok, YouTube, LinkedIn, X; each a direct vendor behind
    the publisher seam (per `integrations/*`).
11. **Internal admin (ActiveAdmin)** — staff console + impersonation + usage credits + audit log
    (per ARCHITECTURE §6).
12. **Hardening** — analytics facade + consent, rate limiting (`rack-attack`), Sentry, RSpec
    coverage, performance indexes, LGPD data export/delete.

---

## 13. Definition of done (per milestone)

- Models annotated; migrations reversible; `[workspace_id, …]` indexes present.
- Every operation has a unit spec; every endpoint a request spec; vendor HTTP webmocked.
- No business logic in controllers; no AR callbacks for side effects; no cross-entity bare `create!`.
- All queries scoped to `Current.workspace`; Pundit authorizes every action.
- Real-time events fire and the SPA invalidates the right queries.
- Secrets only in credentials; per-workspace tokens encrypted; nothing sensitive in `.env` or logs.
- User-facing copy in PT-BR; all identifiers in English; statuses translated via the label map.

---

## 14. Open product decisions (flag, don't block)

- **Image credit pricing** — images debit a flat 1 credit today; revisit the cost-plus rate if
  vendor costs shift materially.
- **Approval/guest portal depth** — guests approve creatives; a richer client review surface is a
  later milestone.
- **Direct integration per network** — every network publishes through its own direct vendor behind
  `SocialPublisher` (see `integrations/README.md`).
- **HeyGen v2 vs v3** — v2 sunsets 2026-10-31; build the vendor against v3, keep v2 as fallback.
- **X API tier** — Free is write-only with no analytics; gate X analytics behind a paid tier
  (see `integrations/x-twitter.md`).
