# Plan — Client central (portal) + campaign-report PDF to client

**Date:** 2026-07-09
**Branch:** `feat/client-portal-and-report-pdf`

Expands the login-less per-client link (`Client#approval_token`, today only an approval queue) into a
full **client central**, and adds a **branded PDF of the campaign report emailed to the client**.

## Locked product decisions (from the user)
1. **Reuse the same link.** `/aprovar/:token` keeps working and now lands on the central. The
   canonical central route is `/portal/:token`; both resolve the same `Client#approval_token`. One
   credential per client.
2. **Report PDF email:** auto-sent on finalize **only when the campaign ran in GO (autopilot) mode**;
   otherwise the team sends it manually via an **"Enviar ao cliente"** button on the report screen.
3. **Campaigns shown in the central:** everything except `draft` (i.e. `active`, `paused`,
   `completed`, `archived`).
4. **Status-driven views** per campaign:
   - `active` / `paused` → **Quadro** (read-only board), **Aprovações** (when pending), **Métricas**
     (real-time).
   - `completed` → **only the Relatório** (the finalized audit deck).
   - `archived` → Relatório if present, else read-only Quadro.
5. **Metrics are real-time** — Action Cable push to a token-scoped public channel (not just polling).

## Foundation that already exists (reuse — do not rebuild)
- **Report** = `ProjectReport` (per project), `data` jsonb deck, born on `Operations::Projects::Finalize`
  → `GenerateProjectReportJob` → `Operations::Reports::GenerateProjectReport`. Rendered by
  `pages/Reports/Show.jsx` at `/relatorios/:id`.
- **Ferrum/Chromium** already installed & wrapped: `Vendors::Render::Html` (HTML→PNG). PDF is a small
  extension (`page.pdf`).
- **Branded mailer**: `@brand_workspace` drives per-agency logo/colors in `layouts/mailer.html.erb`;
  `ApprovalMailer` is the client-facing precedent. No attachment path exists yet (greenfield).
- **Public portal pattern**: `Api::V1::Public::ClientApprovalsController < BaseController`
  (`allow_unauthenticated_access`, `skip_billing_gate`, `resolve_client!` sets `Current.workspace`).
- **Metrics backend**: `Operations::Analytics::PostsOverview.call(workspace:, filters:{project_id:})`
  is already campaign-filterable. Chart primitives in `components/ui/charts/*`.
- **Client-safe ticket payload**: `TicketCardSerializer` (no briefs/notes). `Client#approval_token`,
  `Client.has_many :projects, :tickets through projects`. `Project` status enum
  `{active,paused,archived,completed,draft}`; `completed` = finalized.

---

## Phase 0 — Report → branded PDF → client email  (maps to request part A)

**Backend (create):**
- `app/services/vendors/render/pdf.rb` — `Vendors::Render::Pdf` — Ferrum HTML→PDF (A4, print
  background, `prefer_css_page_size`). Mirrors `Render::Html` browser setup; returns binary PDF bytes.
- `app/views/reports/pdf.html.erb` + `app/views/layouts/report_pdf.html.erb` — a **self-contained,
  inline-CSS** HTML rendering of `report.data` (cover, KPIs, nota geral, wins, formato, gargalos,
  oportunidades, matriz, plano, projeção, growth). Agency-branded header (logo/colors from the
  workspace) + **"powered by agencios.app"** footer.
- `app/services/operations/reports/render_pdf.rb` — `Operations::Reports::RenderPdf.call(report:)` →
  renders the ERB to an HTML string (`ApplicationController.render`) → `Vendors::Render::Pdf` → PDF
  bytes. Attaches to `report.pdf` (ActiveStorage) and returns the blob/bytes.
- `app/services/operations/reports/send_to_client.rb` — `SendToClient.call(report:, sent_by: nil)`:
  guard `report.status_ready?` + `client.email` present; ensure PDF (RenderPdf); `ReportMailer.deck`
  `.deliver_later`; write a history Note via the note operation; stamp `report.sent_to_client_at`.
- `app/mailers/report_mailer.rb` — `ReportMailer.deck(report:, recipients:)` — `@brand_workspace =
  report.project.workspace`, attaches the PDF, subject *"Relatório da campanha — <name>"*, CTA linking
  to the portal report tab. Views: `deck.html.erb` + `deck.text.erb`.
- `app/services/controllers/reports/send.rb` — `require_manager!`, `workspace.projects…reports.find`,
  `Operations::Reports::SendToClient`.

**Backend (modify):**
- Migration: `add_column :project_reports, :sent_to_client_at, :datetime`; `ProjectReport
  has_one_attached :pdf`.
- `Project#go_mode?` — `AutopilotRun.where(ticket_id: tickets.select(:id)).exists? ||
  AutopilotRun.batches.exists?(…project…)`. (Any autopilot run over the project's tickets.)
- `Operations::Reports::GenerateProjectReport#call` — after `status: :ready`, if `@project.go_mode?`
  → `Operations::Reports::SendToClient.call(report: @report)` (auto-send). Guard/rescue so a mail
  failure never fails report generation.
- Routes: `resources :reports, only: %i[show]` → add `member { post :send, action: :send_to_client }`.
- `app/controllers/api/v1/reports_controller.rb` — add `#send_to_client`.
- `ProjectReportSerializer` — expose `sent_to_client_at`, `client_email` (for the button state).
- **Sidekiq mailers queue:** confirm `mailers` queue is processed (Procfile / sidekiq.yml). If absent,
  add `config.action_mailer.deliver_later_queue_name = :default` (flagged by recon).

**Frontend:**
- `reportsApi.sendToClient(id)` in `api/index.js`; `useSendReport(id)` mutation.
- `pages/Reports/Show.jsx` — manager-only **"Enviar ao cliente"** button in the header (disabled +
  tooltip when no `client_email`; shows "Enviado em <data>" from `sent_to_client_at`; toast on send).

**Tests:** `RenderPdf` (produces non-empty `%PDF` bytes; attaches), `SendToClient` (mails to
`client.email` with attachment; noop without email), `GenerateProjectReport` GO auto-send (enqueues
SendToClient when `go_mode?`, not otherwise), request spec `POST /reports/:id/send` (manager 200,
member 403, 402 gate).

---

## Phase 1 — Public portal API (client central backend)

New controller `Api::V1::Public::PortalController < BaseController` (`allow_unauthenticated_access`,
`skip_billing_gate`, `resolve_client!` — reuse the ClientApprovals resolver logic; sets
`Current.workspace`). Routes under `namespace :public`:
- `GET portal/:token` → `Controllers::Public::Portal::Show` → `{ agency:{name,logo_url,primary_color},
  client:{name}, campaigns:[ {id,name,color,status,status_label, counts:{tickets, pending_approval},
  has_report, available_tabs:[…], period:{starts_on,completed_at}} ] }`. Campaigns =
  `@client.projects.where.not(status: :draft)`, ordered active-first.
- `GET portal/:token/campaigns/:project_id/board` → `Controllers::Public::Portal::Board` →
  `{ columns:[ {status, label, tickets:[client-safe card + scope] } ] }` for that project. New
  `Public::PortalCardSerializer` (or reuse `TicketCardSerializer` + a scope block: objective, brief,
  channels, creative_types, subtasks progress, scheduled_at, creative thumbnails count).
- `GET portal/:token/campaigns/:project_id/metrics` → `Controllers::Public::Portal::Metrics` →
  `Operations::Analytics::PostsOverview.call(workspace: @client.workspace, filters:{project_id:})`.
- `GET portal/:token/campaigns/:project_id/report` → `Controllers::Public::Portal::Report` → latest
  ready `ProjectReport` `data` (404/empty when none/generating).
- **Approvals**: reuse existing `client_approvals/:token/*` endpoints unchanged (per client). The
  central's Aprovações tab filters the queue to the selected campaign client-side.

All lookups scoped through `@client.projects.find(project_id)` so a token only ever sees its own data.
Tab availability computed server-side per §Locked decision 4.

**Tests:** request specs — valid token lists non-draft campaigns; board/metrics/report scoped to the
client's project; wrong token 404; a completed campaign exposes only the report tab.

---

## Phase 2 — Real-time metrics channel

- `app/channels/application_cable/connection.rb` — **allow anonymous connects**: set
  `current_user = find_verified_user_or_nil` (do **not** reject when no session). Member-gated channels
  (`Board/Ticket/Generations/Strategy`) already reject nil/non-member, so they stay secure.
- `app/channels/portal_channel.rb` — `PortalChannel`: `subscribed` resolves a `Client` by
  `params[:token]` (approval_token); `stream_from "portal_#{client.id}"` or `reject`.
- `Broadcaster.portal(client, event, payload)` → `broadcast("portal_#{client.id}", …)`.
- `Operations::Posts::SyncMetrics#call` — after the ticket broadcast, also
  `Broadcaster.portal(@post.ticket.project.client, 'metric_updated', post_id:, project_id:)` (guard nil
  client).
- Frontend `usePortalChannel(token, clientId, onEvent)` in `useRealtime.js` → invalidates the portal
  metrics query on `metric_updated`. Metrics query also keeps a modest `refetchInterval` as a safety
  net.

**Tests:** channel spec — valid token streams `portal_<id>`, invalid token rejects; connection spec —
anonymous connect no longer rejected but member channels still reject anonymous.

---

## Phase 3 — Frontend client central

New `app/frontend/pages/Portal/` + `app/frontend/components/portal/`:
- `pages/Portal/Show.jsx` — the central. Branded `Shell` (extract/reuse the Approval `Shell`:
  agency header, `--agency` color, "feito com ✳ Agencios" footer). Two levels:
  1. **Campaign list** (`CampaignList`) — cards per campaign with status pill + counts + a "relatório
     pronto" marker.
  2. **Campaign detail** (`CampaignDetail`) — URL-driven tabs (`?campanha=<id>&aba=<tab>`) rendering
     only the `available_tabs`: **Quadro** (`PortalBoard`, read-only), **Aprovações** (reuse
     `ApprovalTicketCard`/`RequestChangesDialog`, filtered to the campaign), **Métricas**
     (`PortalMetrics`, charts + real-time), **Relatório** (`ReportDeck`).
- `components/portal/PortalBoard.jsx` — read-only board: `WORKFLOW` columns × a static
  `PortalTicketCard` (presentational subset of `TicketCard`: project chip, title, type, channels,
  subtask progress, status). No dnd, no navigation. A ticket opens a read-only scope sheet.
- `components/portal/PortalMetrics.jsx` — reuse `components/ui/charts/*` + `StatCard` (mirror
  `PostsPerformance`); subscribes via `usePortalChannel` for live updates.
- `components/report/ReportDeck.jsx` — **extract** the deck sections from `pages/Reports/Show.jsx`
  into a shared, presentational component consuming `report.data`; used by both the internal report
  screen and the portal report tab (keeps one source of truth, preserves the current aesthetic).
- Data layer: `portalApi` (`show`, `board`, `metrics`, `report`) in `api/index.js`; query keys
  `portal*`; hooks `usePortal(token)`, `usePortalBoard`, `usePortalMetrics`, `usePortalReport` in a new
  `hooks/data/portal.js` re-exported by `useData.js`.
- `App.jsx` — add public routes `/portal/:token` and keep `/aprovar/:token`, both → `Portal/Show`
  (the approvals surface inside it). Both outside `ProtectedRoute`/`Layout`.
- `ApprovalMailer`/`ReportMailer` links point at `/portal/<token>` (approval mail may deep-link
  `?aba=aprovacoes`).

**Verify:** `bin/vite build` clean; drive the portal end-to-end (list → each tab → live metric tick →
report). `bundle exec rspec` green.

## Architecture compliance
- Controllers call services only; logic in `Operations::*`; PDF via `Vendors::Render::Pdf`; mail via
  mailers `.deliver_later`. No AR callbacks — auto-send orchestrated in `GenerateProjectReport`.
- Every query scoped to `Current.workspace` (public controller sets it from the token).
- Never bare-`create!` another entity from a service — Notes via the note operation.
- All code English; UI strings + `/portal`,`/aprovar` segments Portuguese. Dates ISO 8601, money cents.

## Build order
0 → 1 → 2 → 3. Phase 0 ships independently (report PDF/email). Phases 1–3 ship the central. Each phase
commits separately with its tests.
