# Client "Performance" tab — design

**Date:** 2026-07-05
**Status:** Approved (pending spec review)

## Goal

Add a **Performance** tab to the client detail page (`/clientes/:id/desempenho`) that shows all
post-analytics we have for that client, plus AI-generated analysis, filterable by **date range**,
**campaign** (project), **network** (social provider), and **creative type**.

## Context (what already exists)

- **Client detail page** — [app/frontend/pages/Clients/Show.jsx](../../../app/frontend/pages/Clients/Show.jsx)
  already uses URL-based Radix tabs. `TAB_TO_SEG` / `SEG_TO_TAB` maps (≈ line 498) drive the
  `/clientes/:id/:tab` wildcard route (registered in `App.jsx`). Adding a tab is a clean extension.
- **Aggregation reference** — `Operations::Reports::AggregateProjectMetrics`
  (`app/services/operations/reports/aggregate_project_metrics.rb`) is a pure, side-effect-free
  aggregator over a project + fixed window returning `{ period, kpis, content, totals,
  format_breakdown }`. It already sums the latest `PostMetric` per post, computes engagement,
  breaks down by `creative_type`, and merges account-level `AccountMetric` deltas. **This is the
  shape we generalize to client-scope.**
- **Metrics data** — `PostMetric` columns: `reach, views, likes, comments, shares, saves, raw,
  captured_at`. Append-only dated snapshots (never deleted). `engagement` is derived
  (`likes + comments + shares + saves`). `Post#latest_metric` = latest snapshot by `captured_at`.
- **Post → Client chain** — `Post → Ticket → Project → Client`. Network/provider is
  `post.social_account.provider` (no column on Post). Creative type resolution: reuse exactly what
  `AggregateProjectMetrics` does today (per-post `creative_type`) for consistency with project reports.
- **Account-level analytics** — `AccountMetric` (per `SocialAccount`): `followers, new_followers,
  accounts_reached, profile_views, story_replies, views, period_start/end, captured_at`.
- **Charting** — `recharts@^3.9.0` is a dependency but **currently unused**. This feature is its
  first consumer. Existing KPI convention: `StatCard` (`app/frontend/components/ui/page-header.jsx`).
- **Sync reality** — `Operations::Posts::SyncMetrics` runs only for `status_published` posts and
  the scheduled job refreshes only posts published in the last ~30 days. Older posts keep their
  last-captured (frozen) snapshot. `reach`/`saves` are only meaningfully populated on some networks
  (reach ≈ Instagram/Facebook/LinkedIn/X; most video-only networks mirror `reach ← views` and
  report `saves: 0`; X is the only non-Meta network with a real `saves`/bookmark value).

## Decisions

- **Analyses = computed analytics + an AI narrative insight** (uses the existing `Vendors::Ai` seam).
- **Visual = hybrid**: existing `StatCard` for KPIs + `recharts` for trend line & breakdown bars,
  themed to the current Tailwind tokens (preserve the current aesthetic).
- **Include account-level metrics** (follower growth / profile reach) alongside post metrics.
- **AI insight is synchronous for v1** (single fast LLM call over pre-aggregated data, spinner in
  the card). Async-via-cable is a documented fallback if latency proves bad.
- **Tab label = "Performance"**, URL segment `/desempenho`.
- **Architecture: approach A** — build a client-scoped sibling of `AggregateProjectMetrics` rather
  than refactoring it into a shared base (avoids risking the live project-report flow). Keep both
  shaped consistently so a later extraction is trivial.

## Backend

### Data endpoint

`GET /api/v1/clients/:id/performance`
→ `Controllers::Clients::Performance`
→ `Operations::Analytics::ClientPerformance` (pure aggregation, no side effects, scoped to
  `Current.workspace`; verifies the client belongs to the workspace; Pundit-gated like the existing
  client show — internal roles, not `guest`).

**Filter params** (all optional, combinable):

| Param | Meaning | Default |
|---|---|---|
| `from`, `to` | ISO dates, the window | last 30 days |
| `project_ids[]` | campaigns | all client projects |
| `providers[]` | networks (provider enum keys) | all connected |
| `creative_types[]` | creative types | all |

Post scope: `Post.where(ticket_id: Ticket.where(project_id: <client projects>)).status_published`,
`includes(:post_metrics, :social_account, :ticket)`, then filtered by the params above and
`published_at` within `[from, to]`.

**Response** (dates ISO 8601, no pre-formatting):

- `period` — `{ from, to, label, prev_from, prev_to }` (prior equal-length window for deltas).
- `kpis` — `{ reach, views, likes, comments, shares, saves, engagement, posts_count,
  engagement_rate }`, each numeric metric paired with a `*_delta_pct` vs the prior window.
  `engagement_rate = engagement / views` (views is the most universally populated denominator;
  documented in a UI tooltip).
- `account` — per connected network (filtered by `providers`): `{ provider, followers,
  follower_growth, profile_reach, profile_views }` from `AccountMetric` (current vs prior window).
- `timeseries` — daily buckets keyed by `published_at`: `[{ date, views, reach, engagement }]`
  (feeds the recharts trend).
- `by_network` — `[{ provider, posts_count, views, reach, engagement, engagement_rate }]`.
- `by_type` — `[{ creative_type, posts_count, views, reach, engagement, engagement_rate }]`
  (same post→creative_type resolution as `AggregateProjectMetrics`).
- `by_campaign` — `[{ project_id, project_name, color, posts_count, views, reach, engagement,
  engagement_rate }]`.
- `top_posts` — ranked (top ~20 by views): `[{ post_id, label, provider, creative_type,
  project_name, published_at, reach, views, likes, comments, shares, saves, engagement, permalink }]`.
- `meta.metric_support` — per-provider capability map so the frontend renders `—` (not a
  misleading `0`) for metrics a network does not report. Derived from the vendor `SyncInsights`
  actions (e.g. saves unsupported on FB/Threads/TikTok/YouTube/LinkedIn).

### AI insight endpoint

`POST /api/v1/clients/:id/performance/insight` (accepts the same filter params)
→ `Operations::Analytics::ClientPerformanceInsight`
→ new `Prompts::PerformanceInsight` (< `Prompts::Base`, `#system` reads agency name / brand voice
  from `Current.workspace` settings)
→ `Vendors::Ai`.

Input to the prompt is the **already-aggregated** KPIs + breakdowns (not raw posts) → one fast
call. Returns `{ insight: "<markdown>" }`: what worked, what dropped, concrete recommendations.
Recomputed whenever filters change. On failure it raises / surfaces an honest error state in the
card — never a silent empty result.

## Frontend

- **Tabs** — add `performance ⇄ desempenho` to the two maps in `Show.jsx`, plus a
  `<TabsTrigger value="performance">` (lucide `TrendingUp`, label "Performance") and a
  `<TabsContent value="performance">` that renders `<ClientPerformance clientId={id} />`.
- **New component** — `app/frontend/components/client/ClientPerformance.jsx` (keeps `Show.jsx`
  from bloating). Composed of:
  - `FilterBar` — date-range presets (7d / 30d / 90d / custom, default 30d) + campaign, network,
    creative-type multi-selects (options sourced from the client's projects / connected accounts /
    used types). Follows existing filter conventions; collapses into the mobile filter bottom-sheet
    on small screens.
  - `KpiRow` — existing `StatCard`s (post KPIs + account KPIs), each with its delta.
  - `TrendChart` — recharts line/area of views/reach/engagement over time.
  - `NetworkBreakdown`, `TypeBreakdown`, `CampaignBreakdown` — recharts bars + a compact list.
  - `TopPosts` — ranked list with network/type/campaign chips, metrics, permalink.
  - `AiInsightCard` — renders the markdown insight; loading spinner; honest error state.
- **Chart wrappers** — small themed recharts wrappers (`app/frontend/components/ui/charts/`) so the
  first recharts usage is centralized and matches the current tokens/aesthetic.
- **Data layer** — `useClientPerformance(id, filters)` and `useClientPerformanceInsight(id)` in
  `useData.js`; `clientsApi.performance(id, params)` + `clientsApi.performanceInsight(id, params)`
  in `api/index.js`; query key `clientPerformance: (id, filters) => ['clients', String(id),
  'performance', filters]`.
- **Formatting** — numbers/percent/dates formatted on the frontend via the existing formatters.

## Empty & partial states (data honesty)

- No published posts in range → clear "sem posts publicados neste período" state with guidance.
- Posts exist but no metrics yet → "métricas ainda não sincronizadas" note.
- Metrics a network doesn't report → `—` with a one-line footnote, driven by `meta.metric_support`.
- A short note that metrics are refreshed for ~30 days after publish and older values are the last
  captured snapshot.

## Architecture compliance

- Controllers call services only; business logic in `Operations::*`; external AI via `Vendors::Ai`.
- No AR callbacks. Every query scoped to `Current.workspace`. All code in English (UI strings PT).
- Dates ISO 8601, money in cents — formatted on the frontend.
- Never bare-`create!` another entity from a service (n/a — this feature is read-only aggregation
  plus one stateless AI call; it writes nothing).

## Out of scope (v1 / YAGNI)

- Live Action Cable updates on this view (TanStack refetch-on-focus is enough).
- CSV / PDF export of the report.
- Refactoring `AggregateProjectMetrics` into a shared base.
- Async (Sidekiq + cable) AI insight — documented fallback only.
