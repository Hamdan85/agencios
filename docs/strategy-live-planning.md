# Strategy live planning — table & chat in sync

Design guide for the content-strategy planner where the **ticket table is the
canvas** and the **chat is conversation only**. Builds on the async plan pipeline
(`Operations::Strategy::Converse` streams the reply and hands the heavy work to
`Strategy::GeneratePlanJob`, which pushes results over `StrategyChannel`).

## Principles

- The ticket table is the single surface; the chat never renders a preview.
- One source of truth for the table, resolved from the strategy session state.
- Table and chat read the **same** `strategy_session` and subscribe to the **same**
  `StrategyChannel`, so they stay in sync whether the chat is open or closed.
- The proposal phase is **cheap**: the planner tool only produces what's visible in
  the approval/approved card (title, creative types, channels, priority,
  `scheduled_at`, objective, content pillar). **No brief.**
- The expensive brief is generated **when a card becomes a real Ticket** (at
  Approve/materialization), per ticket, async — decoupled from the autopilot GO.

## Table visibility rule

Ghost (proposed) rows appear **only** when a proposal exists **and** the chat is
open. Everything else shows the real tickets.

| Situation | Chat open | Chat closed |
|---|---|---|
| No plan | real tickets | real tickets |
| Proposed plan | **ghosts (dimmed)** | **real tickets** |

```
showGhosts   = hasActiveProposal && chatOpen
tableContent = showGhosts ? planCards : realTickets
```

With the chat closed and a plan pending, a "plan ready" banner still offers
review/approve — but the table itself stays on the real state.

## Table "creating" state

The table-level loading is ephemeral: it shows only between "vou começar a
trabalhar" (`plan_started`) and the first skeleton (`plan_outline`). Once the
empty ghost rows land, the table loader stops — from there the work is a per-card
shimmer while each fills, not a whole-table loader.

## Timeline → Action Cable events

| Beat (what the user sees) | Trigger | Cable event | Table effect |
|---|---|---|---|
| User asks to plan; agent talks | chat stream (SSE) | — | unchanged (real tickets) |
| Agent: "vou começar a trabalhar" | `start_plan` tool in stream | `plan_started` | table loading state |
| Loading stops; N empty rows shimmer | job builds outline | `plan_outline {tickets:[{key,scheduled_at}]}` | N empty ghost rows |
| Rows start filling | job emits card by card | `ticket_drafted {key, fields}` (×N) | each row fills |
| Rows finish | end of batch | `plan_ready` | shimmer stops; status `proposed` |
| Agent: "e aí, aprovado?" | next stream text | — | — |
| User asks to change one ticket | chat stream | `revise_ticket {key, changes}` tool | — |
| Agent: "vou ajustar o rinoceronte…" | stream text | `ticket_revising {key}` | that row only glows |
| Only that ticket updates | job revises 1 card | `ticket_drafted {key, fields}` | that row updates |
| Agent asks to approve again | stream text | — | — |

## Data model — minimum possible

- **No new tables. No real tickets during the proposal.** Everything stays in
  `strategy_session.proposed_plan` (JSON).
- Each `proposed_plan.tickets[]` card gets a stable **`key`** (`t1`, `t2`, …) and a
  **`state`** (`drafting` | `ready` | `revising`) so the table knows what to shimmer.
- Cards carry only approval-visible fields: `title`, `creative_type`(s),
  `channels`, `priority`, `scheduled_at`, `objective`, `content_pillar`. **No `brief`.**

## Backend

Reuses `Converse` + `GeneratePlan` + `StrategyChannel`:

- The streamed chat agent gets intent tools that fire jobs:
  - `start_plan` → enqueue batch generation (the "vou começar" text comes from the stream)
  - `revise_ticket(key, changes)` → enqueue a single-card revision
- `Operations::Strategy::GeneratePlan` emits **card by card** instead of one blob:
  1. broadcast `plan_outline` (count + dates → empty rows immediately)
  2. per card: persist into `proposed_plan`, broadcast `ticket_drafted`
  3. broadcast `plan_ready`
  - Cost: one cheap AI call (no briefs); cards are streamed as they parse. (Upgrade:
    true streaming-parse of the cards call; v1 can stagger.)
- `Operations::Strategy::ReviseTicket(session, key, instruction)` (new, small):
  regenerates just that card → `ticket_revising` then `ticket_drafted`.
- **The brief does NOT run here.**

## Frontend — the table drives

- Move the `StrategyChannel` subscription to the **page** (`Projects/Show`), not
  inside the chat, so the table stays in sync with the chat closed.
- The table renders from `proposed_plan.tickets` (keyed by `key`) when
  `showGhosts`; cable events **patch a single row** by key, never a full reload.
- Shimmer is data-driven: `state: 'drafting'` → skeleton; `ticket_revising` marks a
  card `revising` → glow on that row only.

## Where the heavy work happens — at ticket creation

- On Approve, `Operations::Strategy::Apply` materializes each card into a real
  Ticket; **as each is created**, it fires an async `Operations::Strategy::FillBrief`.
- Each real ticket glows in the table (channel `ticket_<id>`) until its brief lands.
- This is the only place the AI spends tokens writing a brief. **Not** gated on GO.

## Implementation slices (each deployable)

1. **`key` + `state` on `proposed_plan` cards; table matches by key; visibility rule
   (ghosts only when chat open + proposal).** No generation change yet. ← current
2. `GeneratePlan` emits `plan_outline` + per-card `ticket_drafted`; table shows
   empty → filling; page-level channel subscription.
3. `revise_ticket` tool + `Operations::Strategy::ReviseTicket` + per-row shimmer.
4. Drop the brief from the plan; `Apply` fires `FillBrief` per ticket at creation.
5. (Optional) true streaming-parse in slice 2.
