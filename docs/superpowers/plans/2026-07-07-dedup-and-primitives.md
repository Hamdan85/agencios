# Dedup & Primitives Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove duplicated/dead backend code, fix the two service-layer violations, extract the missing frontend UI primitives and migrate every hand-rolled call site onto them, then update the docs to match reality.

**Architecture:** Follows CLAUDE.md exactly — jobs delegate to `Operations::*`, vendor calls go through `Vendors::*::Actions::*`, frontend reuses `components/ui/` primitives. No behavior changes; visual output must stay pixel-identical (user preference: preserve existing design).

**Tech Stack:** Rails 8.1 service objects, RSpec; React 19 + Tailwind v4, Vite.

**Baseline (verified 2026-07-07):** `bundle exec rspec` → 560 examples, 0 failures. `npx vite build` → OK. Every task must end with both still green.

## Global Constraints

- 100% English identifiers; Portuguese only in user-facing strings.
- Never `new` a service — always `.call`.
- No AR callbacks; side effects orchestrated in operations.
- All tenant queries scoped to `Current.workspace`.
- Money in cents, dates ISO 8601, formatting on the frontend.
- Commit after every task (`git add` specific paths; message prefix `refactor:`).
- Preserve visual design exactly when swapping markup for primitives.

---

### Task B1: Delete dead vendor actions + dead services

**Files (delete — all verified zero non-spec references by repo-wide grep):**

```
app/services/vendors/meta/actions/subscribe_page_webhooks.rb
app/services/vendors/meta/actions/subscribe_webhooks.rb
app/services/vendors/meta/actions/start_video_upload.rb
app/services/vendors/meta/actions/transfer_video_chunk.rb
app/services/vendors/meta/actions/finish_video_upload.rb
app/services/vendors/meta/actions/upload_resumable_video.rb
app/services/vendors/meta/actions/get_page_fields.rb
app/services/vendors/meta/actions/get_page_insights.rb
app/services/vendors/meta/actions/get_publishing_limit.rb
app/services/vendors/linkedin/actions/fetch_follower_statistics.rb
app/services/vendors/linkedin/actions/fetch_network_size.rb
app/services/vendors/linkedin/actions/list_posts.rb
app/services/vendors/linkedin/actions/update_post.rb
app/services/vendors/youtube/actions/channel_stats.rb
app/services/vendors/youtube/actions/subscribe_push.rb
app/services/vendors/mercado_pago/actions/create_payment.rb
app/services/vendors/mercado_pago/actions/exchange_o_auth_token.rb
app/services/prompts/best_time_to_post.rb        # never instantiated (documented-but-unbuilt)
app/services/prompts/caption_writer.rb           # GenerateCaptionsJob never existed
app/services/operations/ai/synthesize_idea.rb    # unwired
app/services/prompts/idea_synthesis.rb           # only caller is synthesize_idea
app/services/mcp/unauthorized.rb                 # error class never raised
```

- [ ] Delete files; remove `'synthesize_idea'` entries from `app/models/ai_config.rb:13,26`; delete any specs referencing deleted classes (`grep -rl` in spec/).
- [ ] `bundle exec rspec` → 0 failures. Commit `refactor: delete dead vendor actions and unwired AI services`.

**Do NOT delete (verified live/layered):** X `BuildAuthorizeUrl`+`AuthorizeUrl`, X/LinkedIn `CreatePost`+`PublishPost`, YouTube `RefreshAccessToken`+`RefreshToken`, Meta `Exchange`/`ExchangeCodeForToken`/`ExchangeLongLivedToken`, Meta `PublishMedia`+`PublishPost`, Meta `SyncInsights`+`SyncAccountInsights`, Google `AuthorizeUrl`+`CalendarAuthorizeUrl`, the whole AI seam (`AiAdapter`, `Vendors::Ai`, both clients), `Stripe::ProvisionPlanPrices` (rake), LinkedIn `FetchShareStatistics`/`FetchAdminOrganizations`.

### Task B2: Remove orphaned HeyGen subsystem

Video generation routes exclusively through OpenRouter (`VideoConfig::PROVIDERS = ['', 'openrouter']`; `render_scene.rb:52`). Nothing creates `provider: 'heygen'` generations; `PollHeygenVideoJob` is never enqueued.

**Files:**
- Delete: `app/services/vendors/heygen/` (whole tree), `app/jobs/poll_heygen_video_job.rb`, `app/controllers/webhooks/heygen_controller.rb`, `app/services/controllers/webhooks/heygen/create.rb`, `lib/tasks/heygen.rake`, `spec/services/heygen_webhook_spec.rb`
- Modify: `config/routes.rb` (heygen webhook route), `app/services/operations/creatives/finalize_generation.rb` + `fail_generation.rb` (prune HeyGen branches/comments), `app/models/ai_usage_log.rb` (heygen provider entry if present), `app/jobs/autopilot_watchdog_job.rb:4` (comment), `app/services/creatives/ugc_video.rb` (spec text if it references HeyGen)

- [ ] Read each modify-target first; prune only HeyGen branches, keep shared `FinalizeGeneration`/`FailGeneration` logic intact (live OpenRouter path uses them).
- [ ] `bundle exec rspec` → 0 failures. Commit `refactor: remove orphaned HeyGen video subsystem (video is OpenRouter-only)`.

### Task B3: Extract `Operations::Ai::DraftRetrospective`

**Files:** Create `app/services/operations/ai/draft_retrospective.rb`; Modify `app/jobs/draft_retrospective_job.rb` (job keeps only ticket resolution + delegation); Test `spec/services/operations/ai/draft_retrospective_spec.rb` (move/adapt any existing job spec).

- [ ] Move metrics aggregation + `Prompts::Retrospective` + `AiAdapter.complete` + `ticket.update!(fields:)` + broadcast into the operation, same behavior.
- [ ] `bundle exec rspec` → green. Commit `refactor: extract Operations::Ai::DraftRetrospective from job`.

### Task B4: Extract `Operations::Billing::ReconcileSeats`

**Files:** Create `app/services/operations/billing/reconcile_seats.rb`; Modify `app/jobs/reconcile_seats_job.rb` (keeps sweep + per-workspace error isolation only). Route Stripe calls through `Vendors::Stripe::Actions::*` (reuse `UpdateSubscription` if it fits; otherwise add a discrete action).

- [ ] `bundle exec rspec` → green. Commit `refactor: extract Operations::Billing::ReconcileSeats from job`.

### Task B5: Collapse duplicate brand-assets operations

`Operations::Clients::UpdateBrandAssets` and `Operations::Workspaces::UpdateBrandAssets` are byte-identical except receiver (both attach `logo` / `default_creator_avatar`).

**Files:** Create `app/services/operations/brand_assets/attach.rb` (`call(owner:, logo:, default_creator_avatar:)`); Delete the two variant ops; Modify `app/services/controllers/clients/update_brand_assets.rb` + `app/services/controllers/settings/update_brand_assets.rb` to call the shared op.

- [ ] `bundle exec rspec` → green. Commit `refactor: single brand-assets attach operation for client and workspace`.

### Task B6: Fold `webhooks/meta` into `webhooks/social`

The external Facebook webhook URL must not change: keep the `/webhooks/meta` path, route it to `social#handle` with `defaults: { provider: 'facebook' }`. `Social::Receive` must verify facebook with the default Meta app secret (it already resolves per-provider secrets).

**Files:** Modify `config/routes.rb`; Modify `app/services/controllers/webhooks/social/receive.rb` (accept `facebook`); Delete `app/controllers/webhooks/meta_controller.rb`, `app/services/controllers/webhooks/meta/receive.rb`, `app/services/controllers/webhooks/meta/verify_subscription.rb`; move/adapt any meta webhook specs to the social path.

- [ ] `bundle exec rspec` → green. Commit `refactor: fold meta webhook endpoint into social handler (same URL)`.

### Task B7: DRY serializers + Setting find-or-create

**Files:**
- Create `app/serializers/concerns/post_metrics_payload.rb` (shared `metrics` builder) — include in `post_serializer.rb`, `post_row_serializer.rb`, `post_detail_serializer.rb`; also share the iso8601 date methods.
- Modify `app/serializers/ticket_serializer.rb` to inherit/share `display_title`, `due_date`, `scheduled_at`, `overdue`, `in_alert`, `project` with `TicketCardSerializer` instead of re-declaring.
- Modify `app/services/controllers/settings/{show,update,update_brand_assets}.rb` — extract the duplicated `Setting.find_or_create_by!(workspace:)` into one helper on the `Controllers::Settings` namespace module (same idiom as `Controllers::Clients`).

- [ ] `bundle exec rspec` → green. Commit `refactor: share post metrics payload + ticket serializer fields + settings ensure`.

### Task F1: New frontend primitives

**Files (create):**
- `app/frontend/components/ui/icon-tile.jsx` — `IconTile({ icon: Icon, color, size, rounded })` rendering the `${color}16` tinted tile. Then use it inside `ui/page-header.jsx` (PageHeader + StatCard) and `ui/feedback.jsx` (EmptyState) so the atom lives once.
- `app/frontend/components/ui/section-label.jsx` — `SectionLabel` = the uppercase eyebrow micro-label (`text-[11px] font-bold uppercase tracking-wide text-ink-muted`).
- `app/frontend/components/ui/media-thumb.jsx` — `MediaThumb({ url, aspect, className })` with the `#t=0.1` video/img ternary; shared `isVideoUrl()` goes in `app/frontend/lib/media.js`.
- `app/frontend/components/ui/copy-button.jsx` — `useCopyToClipboard()` + `CopyButton`.
- `app/frontend/hooks/useInfiniteScroll.js` — IntersectionObserver sentinel hook.
- Modify `app/frontend/lib/formatters.js` — add `num()` (pt-BR integer) and `pct()`.

- [ ] `npx vite build` → OK. Commit `feat(ui): IconTile, SectionLabel, MediaThumb, CopyButton, useInfiniteScroll, num()`.

### Task F2: Migrate hand-rolled call sites onto primitives

Batches (each batch: swap conservatively — identical visual output — then `npx vite build`, commit):

- [ ] **F2a** `pages/Billing/**`, `pages/Account/` — icon tiles (11+1), skeletons, `toLocaleString`→`num()`, copy button, pills.
- [ ] **F2b** `components/ticket/**` — pills→`ColorBadge`/`Badge`, `Loader2`→`Spinner`, skeletons→`Skeleton`, media ternaries→`MediaThumb`, eyebrow labels→`SectionLabel` (DoneSummary 11×), EmptyState bypasses, `num()`.
- [ ] **F2c** Remaining pages + components (`Clients`, `Tasks`, `Projects`, `Meetings`, `Invoices`, `Reports`, `Studio`, `Posts`, `Dashboard`, `board/`, `meeting/`, `posts/`, `studio/`, `calendar/`, `layout/`) — icon tiles, pills, spinners, `MEETING_COLOR` import in `MeetingCard`, `PostsFilterBar` native `<select>`→ui primitives, infinite-scroll sentinel in `Tasks/Index` + `ListView`, copy buttons in `Invoices`/`Clients/Show`/`Settings`.
- [ ] Shared ticket-card helpers: extract `TONE` map + accent/due-chip/ring helpers shared by `ticket/TicketRow.jsx` and `board/TicketCard.jsx` into `components/ticket/ticketVisuals.js`.

### Task F3: Consolidate ticket mutations + split useData.js

- [ ] Extract shared invalidation helper (`invalidateTickets(queryClient)`) used by `useBoard.js`, `useTicket.js`, `useData.js` ticket hooks; replace the inline `useMutation` in `pages/Projects/Show.jsx:167` with the shared create mutation.
- [ ] Split `hooks/useData.js` (774 lines) into `hooks/data/<domain>.js` modules; keep `useData.js` as a re-export barrel so all existing imports keep working.
- [ ] `npx vite build` → OK. Commit each.

### Task D1: Documentation update

- [ ] CLAUDE.md: AI path (`Prompts::* → AiAdapter → Vendors::Ai → OpenRouter|Anthropic`), video = OpenRouter scene pipeline (+ Cartesia/FFmpeg; HeyGen removed), billing = prepaid credits (carousel 0 credits, image 1, video cost-based; Stripe meter legacy), vendor roster (add ai/open_router/cartesia/epidemic_sound/jamendo/pexels/ffmpeg/instagram_login/posthog/web/web_push; drop Heygen/Hyperframes), frontend pages/hooks reality (no `Board/` dir; `useData.js`/`useRealtime.js`), captions/best-time prompts removed, new ui primitives list.
- [ ] docs/ARCHITECTURE.md: same corrections (§1 layout, §3, §4 namespaces incl. `autopilot/`, `strategy/`, `credits/`, `video/`, `mcp/`, `approvals/`, `reports/`, `scheduling/`).
- [ ] docs/integrations/README.md: drop HyperFrames/HeyGen, mention OpenRouter video + Cartesia.
- [ ] Commit `docs: align CLAUDE.md + ARCHITECTURE with current AI/video/billing reality`.

### Final verification

- [ ] `bundle exec rspec` full suite → 0 failures.
- [ ] `npx vite build` → OK.
- [ ] `git log --oneline main..` reads as a clean sequence.
