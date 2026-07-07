# Plan — Approval v2: named creatives, media-type slots, 1-of-N selection, campaign rework

Reworks the just-shipped per-creative portal into the model the owner asked for. Synthesises the
squad's UX + engineering proposals. **No DB migrations** — reuse `creatives.approval_state` (add a
`not_selected` enum value, string-backed → code-only), the unused `creatives.name`, and
`Post.media["creative_id"]` (already the single winner pointer set by `Publishers::PostBundle`).

## Mental model (made literal in the UI)
Ticket (has scope) → **Slot** (one media type = `creative_type`) → **Option** (a candidate creative,
1..N) → **decision**. The client decides **per slot**: pick the winning option + approve, OR request
changes on an option. A ticket resolves (advances) when **every slot has an approved winner**.

- **Slot** = `approvable_creatives.group_by(&:creative_type)`, ordered by `creative_types_list`.
- **Option** = an approvable creative (ready, not superseded via `parent_id`, not `not_selected`).
  Multiple options per slot come only from team-added alternatives / explicit "another option" —
  NOT from duplicate type entries (that was the bug).
- **Winner** = the option approved (`approval_state: approved`); ≤1 per slot. Losers → `not_selected`
  (excluded from `approvable_creatives`, so they leave the portal and never publish).
- **fully_approved?** = every slot has an approved winner.

## Decisions (locked)
- **Per-slot approve** (approve each media type independently; auto-advance to next pending slot;
  single-slot ticket → one "Aprovar" resolves it). Request-changes stays per-option.
- Loser state = **`not_selected`**; losers disappear from the portal after selection.
- **Cover/thumbnail/story are their own approvable slots** (client approves the cover too);
  `Publishers::PostBundle` still pairs video+cover downstream.
- Internal team "Aprovar" (`ApproveAll`) auto-picks the **newest** live option per multi-option slot.
- **Delete `DecideCreative`** (dead) + its spec.
- Legacy duplicate creatives from the bug: **leave** as harmless extra options; run the safe
  `creative_types` uniq backfill. (A media-touching cleanup script is out of scope unless asked.)

## Tasks (TDD, green at each step)

**Task 0 — dedup bug fix** (independent, ship first): `.uniq` in `Ticket#creative_types_list`,
`Operations::Tickets::UpdateFields` (column + `fields['scoping']['creative_types']`), and
`Operations::Tickets::Create`. Rake backfill uniqs stored `creative_types`. Tests: model + request
+ KickGenerations (dup types → one creative per unique type).

**Task 1 — creative naming**: `Operations::Creatives::Create` sets `name` (passed `name:` else the
spec label). Serializer already emits `name`. Rake backfill for null names. Frontend name helper
`lib/creativeName.js` (`slotLabel`/`optionLabel`/`pieceName`/`groupIntoSlots` + client-facing type
overrides: ugc_video→"Vídeo", thumbnail→"Capa do vídeo", feed_image→"Imagem").

**Task 2 — `not_selected` + slot helpers**: `Creative` enum adds `not_selected`; `Ticket`
`approvable_creatives` excludes it; add `approval_slots`, `approved_winners`; rewrite
`fully_approved?` per-slot.

**Task 3 — per-slot approve + undo**: `Operations::Approvals::ApproveSlot(ticket:, creative_type:,
chosen_creative_id:, actor:)` — approve winner, siblings → `not_selected`; when it's the last pending
slot, schedule the deferred `OnFullyApprovedJob`. `Undo` reverts approved + not_selected → pending
(within window). Single-option slot auto-picks its sole option.

**Task 4 — winners publish**: `AutoPublishApproved` passes `approved_winners` (not all approvable) →
`Operations::Tickets::Publish` → `Post.media["creative_id"]` = winner; losers get no Post.

**Task 5 — internal ApproveAll**: one winner per slot (newest), rest `not_selected`, advance once.
Delete `DecideCreative` + spec.

**Task 6 — public API**: `Show` payload → `slots: [{ creative_type, label, state, chosen_creative_id,
options: [creative + option_index/option_count] }]`. `ApproveTicket` controller → per-slot
`ApproveSlot`. Rewrite `client_approvals_spec`.

**Task 7 — approval portal UI**: `ApprovalTicketCard` (scope + `SlotSwitcher` [>1 slot] + stage +
`OptionRail` [>1 option] + pinned `ApprovalActionBar`), `BriefSheet` (bottom/right Sheet — fixes the
brief-hides-actions bug), desktop two-pane (queue list + focus), empty/done. `CreativeExperience`
gains `fit="height"` (contain, no forced aspect-square). Named pieces in `RequestChangesDialog`.

**Task 8 — campaign page**: `Projects/Show.jsx` header consolidated (1 primary + `⋯`), approval
block ("⏳ N aguardando cliente" + copiar link). `TicketRow` gets `ApprovalStatusChip` + **inline
assignee picker (assignable row)**. `TicketFilters` gains an approval filter.

Build check `bin/vite build` after each FE task; full `bundle exec rspec` after each BE task.
