# Client approval link, approval-driven lifecycle & posts hub — design

**Date:** 2026-07-05
**Status:** Approved (pending spec review)
**Supersedes:** `2026-07-05-client-performance-tab-design.md` and its plan
`2026-07-05-client-performance-tab.md` — the per-client Performance tab is absorbed into the global
posts hub (§8). Those two docs are marked superseded.

## Goal

Give the agency a **client-facing content approval loop** and make approval the hinge of the posting
lifecycle:

1. A unique, login-less **approval link per ticket** where the client experiences the creatives in
   their native form and approves (or requests changes) **per creative**.
2. **GO (autopilot) stops at `production`** with creatives generated. When every creative is approved
   the ticket **advances into the Publication phase** (`scheduled` / "Postagem") — the existing review
   surface (`PostingPanel`: per-channel captions, creative pick, routing preview, schedule vs.
   publish-now) is **preserved, not skipped** — with a reasonable schedule pre-filled. Whether it is
   then auto-scheduled hands-off or handed to the team to confirm is the `auto_publish_after_approval`
   project setting. The team can always **post manually** at any time.
3. A **project configuration** surface holding the approval + publishing + scheduling behavior
   (migrating the workspace-level `auto_publish_default` down to the project).
4. A global, filterable **posts hub** (`/publicacoes`) with aggregate analytics + a **post detail
   page** carrying all metrics, where content is **experienceable** in the same component used on the
   approval page.
5. **Approval emails**: when a ticket needs approval, the client is emailed the ticket's approval link.
6. The production step's old "aguardando aprovação" select becomes **real state + actions**
   ("Reenviar link", "Aprovar", both confirmed), resolving to **"Aprovado por &lt;actor&gt;"**.

## Context (what already exists)

- **Autopilot** — `AutopilotRun` (`app/models/autopilot_run.rb`) drives a run via
  `Operations::Autopilot::Advance` (`app/services/operations/autopilot/`). Today the ticket-run walks
  `pending → scoping → generating → awaiting_generation → publishing → completed`, ending at ticket
  status `scheduled`: the final `PublishStep` (`publish_step.rb`) moves `production → scheduled` and
  calls `Operations::Tickets::Publish`. `target_status` defaults to `scheduled`,
  `mode` to `scheduled`. Batch (project) GO adds a coordinator row.
- **"Awaiting approval" today** — NOT a state or column. It is a single free-form select field
  `approval_status` (`pending`/`approved`/`changes_requested`) inside the production JSON field bag
  (`app/frontend/components/ticket/FieldGroup.jsx` ≈ lines 84-123; allowlisted in
  `app/services/tickets/fields.rb`). Purely informational — never a publish gate.
- **Creative** (`app/models/creative.rb`) — `creative_type`, `source`, `status`
  (`draft/generating/ready/failed`), `metadata` jsonb, self-referential versions via `parent_id`,
  `has_many_attached :assets`. **No approval field.** Preview today via
  `app/frontend/components/ticket/MediaViewer.jsx` (lightbox) fed by `CreativesPanel`/`PostingPanel`.
- **Post** (`app/models/post.rb`) — status `scheduled/publishing/published/failed/unpublished`;
  Ransack-ready (`ransackable_attributes`/`_associations`); rich `PostSerializer`.
  `PostMetric` (`app/models/post_metric.rb`) — append-only dated snapshots (`reach, views, likes,
  comments, shares, saves, raw, captured_at`); `engagement` derived; `Post#latest_metric`.
  **No global posts index/detail page** — posts are only surfaced inside a ticket. Backend posts are
  nested and `Controllers::Posts::Index` requires `ticket_id`.
- **Posting** — `Operations::Tickets::Publish` (`app/services/operations/tickets/publish.rb`) builds
  posts via `Publishers::PostBundle` (one post per channel; video + cover + story collapse into one),
  `mode: scheduled|immediate`. Publish time resolves `scheduled_at || ticket.scheduled_at`. The cron
  `MonitorScheduledPostsJob` publishes due scheduled posts.
- **Project** (`app/models/project.rb`) — `enum status`; columns `name, description, color, status,
  budget_cents, starts_on, ends_on, client_id, workspace_id`. **No settings blob, no settings page.**
  Edited via `ProjectFormDialog`. `Projects/Show.jsx` is the detail page.
- **Setting** (`app/models/setting.rb`) — one per workspace; `jsonb preferences default: {}`;
  `boolean auto_publish_default`; `encrypts` token columns. This is the pattern to mirror for a
  project-level jsonb settings blob.
- **Client** (`app/models/client.rb`) — has `email` and `phone` columns → approval recipients default
  to `client.email`.
- **Tokenized public links** — two proven patterns: (A) persisted random secret column + unique index
  (`users.mcp_connector_token`, `agc_…`); (B) signed `MessageVerifier` token (`/conectar/:token`,
  `PublicConnectController < ActionController::Base`, `skip_forgery_protection`). Public token-authed
  **API** endpoints already exist (`POST /api/v1/account/email/confirm/:token`,
  `/password_resets/:token`) via `allow_unauthenticated_access` + `skip_billing_gate`.
- **Public React route precedent** — `/confirmar-troca-email/:token` in `App.jsx` is a login-less
  React page (outside `ProtectedRoute`, no `Layout`) calling a token-authed API. Exact template for
  the approval page.
- **Mailer** — `ProjectMailer` shows the agency-branded, client-facing pattern: set
  `@brand_workspace = ticket.workspace` to render the agency's logo/colors; `SomeMailer.method(...)
  .deliver_later` from an operation. From `SystemConfig.mailer_from`; links via `SystemConfig.app_host`.
- **Analytics** — `Operations::Reports::AggregateProjectMetrics` already aggregates the latest
  `PostMetric` per post over a project window → `{ period, kpis, content, totals, format_breakdown }`.
  `recharts@^3.9.0` is installed but unused. The (unbuilt) Performance-tab spec defined a richer
  response shape (kpis + deltas, timeseries, by_network/type/campaign, account, top_posts,
  metric_support) — reused here at workspace scope.

## Decisions (from brainstorming)

1. **Approval granularity = per creative.** The client approves/requests-changes each creative; the
   ticket schedules only when **all** creatives in the approvable set are approved.
2. **Project settings hold:** `require_client_approval`, `auto_publish_after_approval` (migrated from
   workspace `auto_publish_default`), and the posting **window/cadence**. Recipients are **not** a
   project setting — they default to `client.email`.
3. **On full approval:** the ticket **always advances into the Publication phase** (`production →
   scheduled`) — that phase (`PostingPanel`) is preserved and reviews everything. A **reasonable
   schedule** is pre-computed (keep the ticket's planned `scheduled_at` if still future; else the next
   open slot in the project's posting window, avoiding collisions) and stored as the phase's default.
   If `auto_publish_after_approval` is on, the scheduled posts are also created automatically (still
   reviewable/editable in the phase until they fire); if off, the team confirms in the phase (schedule
   or publish immediately).
4. **Posts hub = global, absorbing the Performance analytics.** One hub (`/publicacoes`) with
   aggregate analytics + filterable list + post detail. The per-client Performance tab is superseded.
5. *(locked default)* **AI performance insight is deferred** to a follow-up — not in v1.
6. *(locked default)* **Project settings UI = a "Configurações" tab** on the campaign detail page.
7. *(clarified 2026-07-06)* **The Publication phase (`scheduled` / "Postagem") is never removed** — it
   reviews too much (captions/routing/creative pick/schedule-vs-publish-now). Only autopilot's
   *internal* `PublishStep` is retired. Approval advances the ticket **into** the Publication phase
   (never past it); `auto_publish_after_approval` decides whether posts are auto-created there or the
   team confirms.

## Data model

**`creatives`** (per-creative approval):
- `approval_state` : string, default `"pending"`, null: false — enum
  `{ pending, approved, changes_requested }`, prefix `approval_`.
- `client_feedback` : text — the "pedir ajustes" comment.
- `decided_at` : datetime.
- `reviewed_by_type` / `reviewed_by_id` : polymorphic — **User** (internal "Aprovar") or **Client**
  (via link). Drives "Aprovado por &lt;actor&gt;".

**Approvable set & full approval (derived, no stored flag):**
- Approvable set = a ticket's `status_ready`, **non-superseded** creatives (exclude any creative that
  has a newer version, i.e. is referenced as another creative's `parent_id`).
- `Ticket#fully_approved?` = the approvable set is non-empty and every member is `approval_approved`.
- `Ticket#approval_actor` = the `reviewed_by` of the last-decided approved creative (for display).

**`tickets`:**
- `approval_token` : string, unique index — random secret (`SecureRandom.urlsafe_base64(32)`),
  lazily minted (`Ticket#approval_token!`), powers `/aprovar/:token`. Persisted (not signed) so
  "reenviar link" reuses the same URL and it stays revocable.
- `approval_requested_at` : datetime — last time the link was emailed (status line + "reenviado em").

**`projects`** — new `settings` jsonb, default `{}`, null: false (mirrors `Setting#preferences`):
- `require_client_approval` : bool.
- `auto_publish_after_approval` : bool.
- `posting_window` : `{ weekdays:[1,2,3,4,5], times:["09:00","12:00","18:00"], min_gap_minutes:120,
  timezone:"America/Sao_Paulo" }`.
- A resolver (`Project#setting(key)`) falls back to the workspace default where one exists (notably
  `auto_publish_after_approval` ← `Setting#auto_publish_default`).

**Migration of `auto_publish_default`:** keep the `Setting` column as the org default and seed of new
projects; per-project `auto_publish_after_approval` overrides it. (No destructive removal of the
workspace column in v1.)

**Removed:** the `approval_status` production field — dropped from the `FieldGroup` production schema
and from the `app/services/tickets/fields.rb` `production` allowlist. Existing values are ignored
(the new derived state is authoritative); no data backfill required.

## Backend services (`.call`, English, scoped to `Current.workspace`)

New namespace `Operations::Approvals::*`:
- `RequestApproval(ticket:, sent_by:)` — ensure `approval_token`, set `approval_requested_at`, send
  `ApprovalMailer.request`, write a history `Note`. Called by autopilot completion **and** "Reenviar
  link". Never bare-creates a Note — uses the existing note operation.
- `DecideCreative(creative:, decision:, actor:, feedback: nil)` — set the creative's approval fields +
  `reviewed_by`. On `changes_requested`: keep ticket in `production`, notify the team (existing
  note/notification path). Then evaluate `fully_approved?` → `OnFullyApproved` when true.
- `ApproveAll(ticket:, actor:)` — internal "Aprovar": mark the whole approvable set approved with
  `reviewed_by = actor` (a User). Then `OnFullyApproved`.
- `OnFullyApproved(ticket:)` — write the "Aprovado por &lt;actor&gt;" Note; compute a reasonable moment
  via `Scheduling::NextSlot` and store it on `ticket.scheduled_at` (the Publication phase's default);
  **always** advance `production → scheduled` via `Operations::Tickets::ChangeStatus(force: true)` so the
  ticket **enters the (preserved) Publication phase**. Then, **only if** the project resolves
  `auto_publish_after_approval` true, call `AutoPublishApproved`; otherwise stop — the team reviews and
  confirms in the Publication phase (`PostingPanel`).
- `AutoPublishApproved(ticket:)` — the hands-off branch: **reuse** `Operations::Tickets::Publish(ticket:,
  user: nil, creative_ids: <approved set>, mode: 'scheduled', scheduled_at: ticket.scheduled_at)` to
  create the scheduled posts (still reviewable/editable in the Publication phase until they fire). This
  is the only publish path — no new one. (Replaces the earlier `ScheduleApproved`.)

New `Operations::Scheduling::NextSlot(project:, desired_at:)` — **pure**, unit-tested: returns
`desired_at` if it is in the future, inside the window, and collision-free (≥ `min_gap_minutes` from
the project's other `scheduled` posts); otherwise the earliest window slot
`≥ max(Time.current, desired_at)` that is collision-free. Reads `project.setting(:posting_window)`.

## Autopilot change (GO stops at production)

Surgical edits to the ticket-run:
- `AutopilotRun`: `target_status` default → `"production"`; drop `publishing` from `ACTIVE_STATES`.
- `Advance`: remove the `publishing` case. When generations settle
  (`KickGenerations` all-sync path and `OnGenerationSettled.reconcile`), transition the run to
  `completed` at ticket status `production` instead of `publishing`/`scheduled`.
- Delete/retire autopilot's **internal** `PublishStep` only (an autopilot *code* phase — **not** the UI
  Publication phase, which stays). Its post-creation responsibility now lives in
  `Operations::Tickets::Publish`, invoked by `AutoPublishApproved` on approval (when auto-publish is on)
  or by the team directly in the Publication phase.
- On run completion at production, if `project.setting(:require_client_approval)` → call
  `Approvals::RequestApproval(ticket:, sent_by: run.user)` so the client is emailed automatically.
- Batch (project) GO: unchanged orchestration; children now finish at production.
- Credit gate is unchanged (creatives are still generated during the run).

## Public approval experience — `/aprovar/:token`

- **React route** outside `ProtectedRoute`, no `Layout`, in an **agency-branded** client shell
  (workspace logo/colors). Mirrors `ConfirmEmailChange`. Page: `app/frontend/pages/Approval/Show.jsx`.
- **Public API** `Api::V1::Public::ApprovalsController` (`allow_unauthenticated_access`,
  `skip_billing_gate`): resolves ticket + workspace from `approval_token`, sets `Current.workspace`
  so serializers work, Pundit not applied (token is the credential).
  - `GET  /api/v1/public/approvals/:token` → `{ branding, campaign, creatives:[{id, type,
    approval_state, caption, client_feedback, experience{...asset urls/kind/slides}}], plan:{networks,
    planned_at}, approved:bool }`.
  - `POST /api/v1/public/approvals/:token/creatives/:id/approve`
  - `POST /api/v1/public/approvals/:token/creatives/:id/request_changes` (feedback)
  - Actor = the token's `Client`. Delegates to `Operations::Approvals::DecideCreative`.
- Page renders each creative in its native `CreativeExperience` (§ shared) with **Aprovar** /
  **Pedir ajustes** per creative, shows the caption + where/when it will post, and a completion state
  when all are approved. Honest error state for an invalid/expired/revoked token.

## Emails

- `ApprovalMailer.request(ticket:, recipients:)` — agency-branded (`@brand_workspace =
  ticket.workspace`), to `client.email`, subject *"Aprove o conteúdo — &lt;campanha&gt;"*, CTA button
  → `#{app_host}/aprovar/#{token}`. `deliver_later` from `RequestApproval`.
- Team notification when the client requests changes — reuses the existing note/notification path
  (no new client-facing mail).

## Production step redesign

`FieldGroup` production view loses the `approval_status` select and gains an **Approval panel**:
- **Not yet approved** → derived status line *"Aguardando aprovação do cliente"* (+ "reenviado em
  &lt;data&gt;" when `approval_requested_at` is set) and two confirmed actions: **"Reenviar link"**
  (→ `RequestApproval`) and **"Aprovar"** (→ `ApproveAll`).
- Any creative `changes_requested` → its `client_feedback` shown inline so the team can regenerate.
- **Fully approved** → **"Aprovado por &lt;actor&gt; · &lt;data&gt;"** (actor = User or Client name).
- **Badge persists into the Publication phase.** Because full approval advances the ticket into
  `scheduled` (§Decision 7), the "Aprovado por &lt;actor&gt;" state is shown wherever the ticket now is:
  the Approval panel renders in **both** `production` (aguardando + actions) and `scheduled` (the
  "Aprovado por &lt;actor&gt;" badge). The approval summary is a ticket-level derivation, not a
  production-only field.
- Manual posting stays available in the `scheduled` step; when `require_client_approval` is on and the
  ticket is not approved, the posting action shows a soft confirmation ("Postar sem aprovação?").

## Posts hub — `/publicacoes` (global; absorbs Performance)

New top-level nav item (Portuguese segment; adjustable). The per-client Performance tab is not built.

- **`app/frontend/pages/Posts/Index.jsx`**:
  - **Analytics header** — KPIs + trend + breakdowns from a new
    `Operations::Analytics::PostsOverview` (workspace-scoped, filterable generalization of
    `AggregateProjectMetrics`; reuses `recharts`; metric-support aware → `—` where a network doesn't
    report a metric).
  - **Filters**: client, campaign, network (provider), creative type, status, date range, search.
    Mobile filter bottom-sheet (existing convention).
  - **Post list**: thumbnail + channel + client/campaign chips + status + date + key metrics.
- **`app/frontend/pages/Posts/Show.jsx` — `/publicacoes/:id`**: the content in its `CreativeExperience`
  + **all metrics** (latest snapshot + trend chart over the `PostMetric` history + full breakdown) +
  metadata (account, caption, permalink, scheduled/published dates, links to ticket/campaign/client).
- **Backend**: global `Controllers::Posts::Index` (Ransack filters, `ticket_id` optional),
  `Controllers::Posts::Show`, `Controllers::Posts::Overview`; new `PostDetailSerializer` with metric
  history. Routes add top-level `GET /api/v1/posts` (filtered), `GET /api/v1/posts/:id`, and
  `GET /api/v1/posts/overview` alongside the existing nested posts routes.
- **Client page link**: a "Ver desempenho" action on `/clientes/:id` deep-links to
  `/publicacoes?client=:id`.

## Shared component

Extract **`CreativeExperience`** (inline native rendering: carousel swiper / video player / image)
into `app/frontend/components/creative/`, reused by the posts detail **and** the approval page. Keep
`MediaViewer` (lightbox) for zoom; `CreativeExperience` may open it.

## Project settings UI

A **"Configurações" tab** on `Projects/Show.jsx` (segment under the existing detail page) with a form
for `require_client_approval`, `auto_publish_after_approval`, and the posting window (weekday
toggles + time list + min gap + timezone). Backend: `Controllers::Projects::UpdateSettings`
(`require_manager!`, workspace-scoped) writing the `settings` jsonb via
`Operations::Projects::UpdateSettings`; `ProjectSerializer` exposes `settings` (resolved with
workspace fallbacks).

## Architecture compliance

- Controllers call services only; business logic in `Operations::*`; publishing only via
  `Operations::Tickets::Publish` → `Publishers::SocialPublisher`.
- No AR callbacks — approval side effects (email, notes, scheduling) orchestrated in operations.
- Never bare-`create!` another entity from a service — Notes/Posts created via their own operations.
- Every query scoped to `Current.workspace` (the public controller sets it from the token).
- Status changes only via `Operations::Tickets::ChangeStatus` (approval→schedule moves
  `production → scheduled` through it, then `Operations::Tickets::Publish` creates the posts).
- All code English; UI strings + the `/aprovar` URL segment Portuguese. Dates ISO 8601, money cents.

## Build order (phases for the plan)

- **A** — Migrations (creatives approval fields; tickets token + `approval_requested_at`; projects
  `settings`), model helpers, project settings backend + "Configurações" tab.
- **B** — `Operations::Approvals::*` + `Scheduling::NextSlot`; autopilot GO→production change;
  wire `RequestApproval` on production entry.
- **C** — Public approval API + `/aprovar/:token` React page + `ApprovalMailer` + `CreativeExperience`.
- **D** — Production-step redesign (remove select; approval panel + confirmed actions).
- **E** — Posts hub: `PostsOverview` + global posts index/detail endpoints + `/publicacoes` pages +
  client "Ver desempenho" deep link.

Each phase is independently shippable; tests accompany each (RSpec for services/serializers/public
controller; `NextSlot` gets thorough unit coverage).

## Out of scope (v1 / YAGNI)

- AI performance insight in the hub (deferred follow-up).
- A client-wide "all my pending approvals" dashboard (approval is per-ticket link).
- Per-channel caption approval (client approves creatives; the plan is shown for context).
- CSV/PDF export; live Action Cable on the hub (TanStack refetch is enough).
- Removing the workspace `auto_publish_default` column (kept as fallback/default).
