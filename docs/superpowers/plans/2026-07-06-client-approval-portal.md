# Plan — Per-client branded approval portal

Reworks the just-shipped **per-ticket** approval into a **per-client portal**: one link per
client, showing that client's queue of tickets currently awaiting approval, one item at a time
(no scroll), branded to the agency + "powered by Agencios". Decisions leave the queue; GO-mode
change requests regenerate only the flagged creative with the client's feedback; a credit shortage
alerts the workspace admins; approval continues the ticket's normal flow.

## Product decisions (locked)
- **Change requests are per-creative**: the client points at one piece and only that piece is
  regenerated (selector required when a ticket has >1 approvable creative). Approval is per-ticket
  (approves all currently-pending creatives).
- **Approve has a 5s Undo**: approval persists server-side immediately; the flow-advancing side
  effect (`OnFullyApproved` → advance/auto-publish) is deferred ~6s and guarded, so Undo reverts
  cleanly and a closed tab still commits.
- **Replace, don't keep both**: the brand-new per-ticket public page/route is repurposed to the
  client token; no dual model.

## Mechanism notes (grounded in the code)
- Superseding: a regenerated creative is a new `Creative` with `parent_id` = old id; `version+1`.
  `Ticket#approvable_creatives` already excludes superseded ones.
- "In portal" = a pending ticket for the client: `approval_requested_at` present AND it has an
  approvable creative still in `approval_state: pending`. Approve-all → `fully_approved?` → advances
  → leaves. Any creative sent to `changes_requested` → leaves; a fresh creative + new
  `RequestApproval` brings it back.

---

## Task 1: Client approval token + pending-queue scope
- Migration: `clients.approval_token` (string, unique index, nullable).
- `Client#approval_token!` (idempotent mint, `apv_…`), `Client#revoke_approval_token!`.
- `Ticket` scope `awaiting_client_approval` + predicate `pending_client_approval?` (approval_requested_at
  present AND any approvable creative `approval_pending?`).
- `Client#pending_approval_tickets` = tickets across the client's projects matching the scope.
- Test: model spec — scope includes a requested+pending ticket, excludes approved/changes/none.

## Task 2: Per-client public API
- `Controllers::Public::ClientApprovals::Show` — resolve client by token; return `{ agency:{name,logo,color},
  client:{name}, tickets:[ {id, title, objective, brief, channels, creative_type, scheduled_at,
  creatives:[CreativeSerializer]} ] }` (only pending tickets, only pending/approvable creatives shown for decision).
- `…::ApproveTicket` (approve all pending creatives = `ApproveAll`, then schedule deferred OnFullyApproved),
  `…::RequestChanges` (creative_id + feedback), `…::Undo` (revert a just-approved ticket within the window).
- Routes under `namespace :public`: `get 'client_approvals/:token'`, `post '…/:token/tickets/:ticket_id/approve'`,
  `post '…/request_changes'`, `post '…/undo'`. Keep old `/aprovar/:token` frontend path → client token.
- Request spec: token returns only pending tickets; approve advances after the window; wrong token 404.

## Task 3: RequestChanges operation (per-creative) + routing
- `Operations::Approvals::RequestChanges.call(creative:, feedback:, actor:)` — mark the creative
  `approval_changes_requested` + store `client_feedback` + `decided_at` + `reviewed_by`; write a note.
- Then route: if the ticket is under an active autopilot run → `Operations::Autopilot::Regenerate`
  (Task 5); else move the ticket back to `production` (via ChangeStatus) and notify the team (note/push).
- Spec: sets state + feedback; GO ticket triggers Regenerate; manual ticket returns to production.

## Task 4: Deferred approval + Undo
- `ApproveAll` stays (marks approved). Public ApproveTicket enqueues `OnFullyApprovedJob` with
  `wait: 6.seconds` instead of calling inline. `OnFullyApproved` guards on `ticket.fully_approved?`
  at run time (undo → some creative back to pending → no-op).
- `…::Undo` reverts the ticket's just-approved creatives to `approval_pending` (guard: only within
  window, only if not yet advanced).
- Spec: approve → undo before window → ticket NOT advanced; approve → no undo → advanced.

## Task 5: GO feedback → regeneration loop
- `Operations::Autopilot::Regenerate.call(run:, creative:, feedback:)` — supersede `creative`
  (new Creative, parent_id set, version+1), thread `feedback` into the generation prompt
  (`Prompts::*` / `Operations::Creatives::Generate*` via a `revision_notes:`/`feedback:` arg),
  re-enter the run (park `awaiting_generation`), and on ready → `RequestApproval` again.
- Credit preflight first (Task 6). Reuse KickGenerations/OnGenerationSettled where possible.
- Spec: regenerate supersedes + carries feedback into the generation; on settle re-requests approval.

## Task 6: Credit-shortage admin notification
- Preflight in Regenerate: `needed = Pricing.credits_for(...)`; if `workspace.credits_available < needed`
  → `Operations::Credits::NotifyAdmins.call(workspace:, context:)` and stop (leave the creative in
  changes_requested; the client's feedback is preserved for when credits arrive).
- Recipients: owner/admin memberships' users. Email (branded mailer) + `Operations::Push::Notify`.
- Idempotent: dedupe on a per-workspace timestamp/window so retries don't spam.
- Spec: insufficient credits → notifies each admin once, does not regenerate.

## Task 7: Email link → client token
- `RequestApproval` / `ApprovalMailer.review` point the link at `/aprovar/<client.approval_token>`
  (client portal) instead of the ticket token. Mint the client token in RequestApproval.
- Spec: mail body contains the client-token URL.

## Task 8: Frontend API + hooks
- `approvalsApi`: `get(token)` (client queue), `approveTicket(token, ticketId)`,
  `requestChanges(token, ticketId, {creativeId, feedback})`, `undo(token, ticketId)`.
- `usePublicApproval(token)` returns the queue; mutation helpers with optimistic queue updates.

## Task 9: The branded deck UI (per UX proposal)
- `pages/Approval/Show.jsx` rewrite + `components/approval/`: `ApprovalShell`, `ApprovalDeck`,
  `PendingTicketCard`, `TicketScope`, `CreativeReel` (delegates to `CreativeExperience`),
  `BriefSheet`, `RequestChangesDialog` (per-creative selector + textarea + quick-picks),
  `ApprovalEmptyState`, `ApprovalDoneState`, `confetti.js`, `lib/color.js` (`readableOn`).
- 100dvh no-scroll shell, agency-color theming (`--agency`), 5s Undo toast on approve,
  "feito com ✳ Agencios" signature. Reuse the design system; no native dialogs.
- Verify: `bin/vite build` clean.

## Task 10: Cleanup old per-ticket public path
- Remove/redirect the per-ticket `Controllers::Public::Approvals::*` + routes now that the client
  portal supersedes them (keep internal ticket approval actions — D2 — intact).
- Full suite green + build clean.
