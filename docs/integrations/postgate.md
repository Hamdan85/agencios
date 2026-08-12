# PostGate — Social Publishing Aggregator (https://postgate.studio)

> Postproxy-compatible, multi-tenant social publishing infrastructure. One API key, one HTTP
> surface, thirteen platforms (`sandbox`, `facebook`, `instagram`, `threads`, `linkedin`,
> `bluesky`, `mastodon`, `telegram`, `tiktok`, `youtube`, `pinterest`, `google_business`, `x`).
> PostGate owns each platform's OAuth app, token refresh, and publishing-payload translation —
> agencios only ever talks to the PostGate REST API.

## 0. What you'll build

- A **hosted connection flow**: agencios asks PostGate for a connect URL per platform, redirects
  the user's browser to it, and PostGate handles that platform's OAuth end-to-end, redirecting
  back into agencios when done.
- **Publishing**: one `POST /api/posts` call fans out to one or more connected profiles
  (`Target`s), each delivered asynchronously per platform.
- **Analytics**: stored hourly snapshots (`post.insights` / `GET /api/posts/stats`) for most
  platforms, plus a live read for Pinterest (`GET /api/posts/{id}/live-stats`) and a
  cross-platform growth timeseries.
- **Webhooks**: PostGate pushes post/profile lifecycle and analytics events instead of agencios
  polling.

| Concern | Class |
|---|---|
| Low-level HTTP | `Vendors::Postgate::Client` |
| Post-aware publish/sync actions, webhook handling | `Operations::Posts::*` / `Controllers::Webhooks::Postgate` *(owned by a separate workstream — not covered by this doc)* |

## 1. Credentials

Two app-level secrets, both in Rails encrypted credentials (`rails credentials:edit`), with an
ENV fallback for local dev per the project's `credential(*path, env:)` convention:

| Credential | ENV fallback | Used for |
|---|---|---|
| `postgate.api_key` | `POSTGATE_API_KEY` | `Authorization: Bearer <api_key>` on every `/api/*` call |
| `postgate.webhook_secret` | `POSTGATE_WEBHOOK_SECRET` | Verifying `X-PostGate-Signature` on inbound webhooks |

`Vendors::Postgate::Client.configured?` reports whether `postgate.api_key` is present.
`SystemConfig.postgate_enabled?` additionally checks the `POSTGATE_DISABLED` env var (an
emergency kill switch — set it to `'true'` to force the integration off without pulling the key,
e.g. during a PostGate outage) — gate any PostGate-dependent UI/behavior on this, not on
`configured?` alone.

There is no per-workspace OAuth app to register — PostGate is single-tenant from agencios' point
of view: one API key for the whole platform, every workspace's connected accounts (`Profile`s)
live under it, grouped by `ProfileGroup` (one group per workspace is the natural mapping).

## 2. Hosted connect flow

1. **Register the return origin once**, per environment (dev/staging/prod):
   `POST /api/connect-origins` with `{ origin, label }`. PostGate only redirects back to a
   registered origin (or its own built-in baseline origin, returned under `meta.built_in` from
   `GET /api/connect-origins`) — an unregistered `return_url` is rejected at connect-URL
   creation. `Client#connect_origins` / `#allow_connect_origin(origin:, label: nil)`.
2. **Request a connect URL**: `POST /api/profiles/connect` with `{ platform, profile_group_id?,
   return_url?, instance_url? }` → `Client#create_connect_url`. Returns
   `{ platform, url, expires_in }` — `url` is a short-lived (`expires_in` seconds) hosted page;
   redirect the user's browser to it.
   - `profile_group_id` scopes the new profile to a workspace's group (map 1 workspace → 1
     `ProfileGroup`, created via `Client#create_profile_group`).
   - `instance_url` is **required for Mastodon** (the instance the account lives on, e.g.
     `https://mastodon.social`) and ignored for every other platform.
3. **PostGate redirects the browser back** to `return_url` with query params appended:
   - Success: `?connected=<platform>&connection_platform=<platform>`
   - Failure: `?connection_error=<reason>&connection_platform=<platform>`
4. The newly connected account is now a `Profile` — `GET /api/profiles` (optionally filtered by
   `profile_group_id` / `platform`) lists it; `GET /api/profiles/{id}/health` reports token
   health (call this on a schedule to catch `reauth_required` before a publish fails).
5. **Historical backfill** (optional): `POST /api/profiles/{id}/import` queues an async job that
   lists posts already published on the provider account (before the PostGate connection, or by
   another tool) and creates them locally with `created_via: "imported"`. It also runs
   automatically right after a successful connection. Not every platform supports it — see
   `features.import` per platform in `GET /api/platforms`; unsupported platforms return a
   `platform_not_configured` error. Media is never downloaded, only lightweight metadata.

Disconnecting (`DELETE /api/profiles/{id}`) revokes provider credentials where supported and
stops future deliveries, but **never deletes publication history** (targets, permalinks,
analytics stay queryable). Calling delete again on an already-disconnected profile removes it
from listings entirely; reconnecting the same provider account makes it visible again.

## 3. Publishing

`POST /api/posts` — `Client#create_post(payload, idempotency_key: nil)`. `payload` is the full
body:

```ruby
{
  post: {
    body: "Caption text",
    scheduled_at: "2026-09-01T15:00:00Z",   # or the literal string "queue"; omit to publish now
    timezone: "America/Sao_Paulo",           # default UTC
    draft: false,
    options: {
      youtube: { title: "...", privacy: "public", made_for_kids: false, community_guidelines_confirmed: true },
      pinterest: { board_id: "..." }
    }
  },
  profiles: ["profile_abc123"],              # profile IDs, or an unambiguous platform slug
  media: ["https://cdn.example.com/a.mp4"]   # media IDs, public HTTP(S) URLs, or base64 data URLs
}
```

- **Delivery is always asynchronous per target.** The `201` response is the `Post` in `draft` /
  `scheduled` / `processing` status with one `Target` per profile, each starting `pending` — it
  is **not** a synchronous per-network publish confirmation. Poll `GET /api/posts/{id}` or
  `GET /api/posts/{id}/logs`, or (preferred) consume the `post.published` / `post.failed` /
  `post.partial` webhooks (§5). A `partial` post status means some targets published and others
  failed — check each `Target#status`/`error_code`/`error_message`.
- **`Idempotency-Key` header** (`create_post(payload, idempotency_key:)`): reusing the same key
  with the same request returns the original `Post` for 72 hours instead of creating a
  duplicate — always set one per logical publish attempt (e.g. the agencios `Post` id + a retry
  counter), the same discipline as Mercado Pago's `X-Idempotency-Key`.
- **Per-platform required options** (rejected without them):
  - `youtube` — `options.youtube` requires `title`, `privacy` (`private`/`unlisted`/`public`),
    `made_for_kids`, and `community_guidelines_confirmed: true`.
  - `pinterest` — `options.pinterest.board_id` is mandatory on every Pin. Resolve it first via
    `Client#list_boards(profile_id)` (`GET /api/profiles/{id}/boards`) — PostGate reads the
    board list live from Pinterest (not stored) so a picker can be rendered instead of asking
    for a raw ID; a profile connected via Sandbox, or before `boards:read` was requested, must
    be reconnected before boards are readable.
- `PATCH /api/posts/{id}` (`update`) only works on `draft`/`scheduled` posts, not ones already
  publishing. `DELETE /api/posts/{id}` cancels a draft/scheduled post.

### Platform media matrix

| Platform | Media limit | Notes |
|---|---|---|
| `facebook` | 10 | |
| `instagram` | 10 | |
| `threads` | 20 | |
| `linkedin` | 9 | |
| `tiktok` | 35 | **Draft-only** delivery (lands in the creator's TikTok inbox, not auto-published) |
| `youtube` | 1 | Video only; requires `options.youtube` (see above) |
| `pinterest` | 1 | Requires `options.pinterest.board_id` |
| `bluesky` | 4 | Images only, no video; body capped at 300 chars |
| `mastodon` | 4 | Body capped at 500 chars; per-instance limits may be stricter (`instance_url` at connect time) |
| `telegram` | 10 | The bot must be an admin of the target channel |
| `google_business` | 1 image | Body capped at 1,500 chars |
| `x` | 4 | |

This table is a snapshot — always cross-check `GET /api/platforms` (`Client#platforms`) at
runtime, since PostGate ships platform-capability changes without a agencios deploy.

## 4. Analytics

Three different shapes, matched to how each provider actually exposes data — do not mix them up:

- **Stored hourly snapshots** — `GET /api/posts/stats?post_ids=<comma-joined>&from&to` →
  `Client#post_stats(post_ids:, from: nil, to: nil)`. Append-only; covers every platform
  **except Pinterest**.
- **Pinterest live read** — `GET /api/posts/{id}/live-stats` → `Client#live_stats(post_id)`.
  Fetches Pin analytics live per published Pinterest target; nothing is persisted by PostGate,
  so every call hits Pinterest directly. Per-target failures land under `errors` in the response
  instead of failing the whole call. Requires the `analytics` plan feature.
- **Cross-platform growth timeseries** — `GET /api/analytics/timeseries` →
  `Client#analytics_timeseries(from:, to:, platform:, profile_id:, profile_group_id:, compare:)`.
  Daily metric *increases* (not cumulative totals) by platform/profile group, with an
  equally-sized previous-period comparison when `compare` (default `true`). Also gated behind
  the `analytics` plan feature (403 without it — check `GET /api/quotas` /
  `Client#quotas` for the workspace's entitlements up front).
- **Per-profile snapshots** — `GET /api/profiles/{id}/stats` → `Client#profile_stats(id, from:,
  to:)` — account-level analytics (followers etc.) rather than per-post.

## 5. Webhooks

`POST /api/webhooks` (`Client#create_webhook(url:, events:)`) registers an endpoint; the create
response shows the signing secret **once** — store it as `postgate.webhook_secret` immediately,
it cannot be re-fetched. `Client#list_webhooks` / `Client#delete_webhook(id)` manage the rest.

### Signature verification

Every delivery carries `X-PostGate-Signature: t=<unix_ts>,v1=<hex_hmac>`, where
`hex_hmac = HMAC-SHA256(webhook_secret, "<t>.<raw_request_body>")` (same shape as Stripe/Mercado
Pago's timestamped-HMAC schemes already used elsewhere in this codebase — reject if the
timestamp is stale to guard against replay, and always compare with
`ActiveSupport::SecurityUtils.secure_compare`, never `==`).

### Event envelope

```json
{ "id": "evt_...", "type": "post.published", "occurred_at": "2026-08-12T15:04:05Z", "data": { "...": "..." } }
```

### Event catalog

| Event | Fires when |
|---|---|
| `post.draft` | A post is created in `draft` status |
| `post.scheduled` | A post is scheduled |
| `post.published` | Every target of a post delivered successfully |
| `post.partial` | Some targets delivered, others failed |
| `post.failed` | Every target failed |
| `post.insights` | A stored analytics snapshot was captured for a post |
| `profile.connected` | A hosted connect flow finished successfully |
| `profile.disconnected` | A profile was disconnected (by the user or via `DELETE /api/profiles/{id}`) |
| `profile.expiring` | A connected profile's token is nearing expiry |
| `profile.expired` | A connected profile's token expired — carries `data.reason`: `token_expired`, `refresh_failed`, `revoked`, or `publish_auth_error` |
| `profile.reauth_required` | The profile needs the hosted connect flow re-run before it can publish again — same `reason` values as `profile.expired` |
| `profile.stats_updated` | A profile-level analytics snapshot was captured |
| `stats.updated` | A general stats refresh completed |
| `comment.created` | An inbound comment arrived (Instagram engagement rollout) |
| `message.received` / `message.sent` | DM/conversation activity (Instagram engagement rollout) |
| `automation.executed` / `automation.failed` | A comment-to-DM automation ran — currently gated to workspaces enrolled in the Instagram engagement rollout |

Prefer `profile.reauth_required` / `profile.expired` over polling `GET /api/profiles/{id}/health`
for every connected account — react to the push, poll health only as a periodic safety net.

## 6. Client interface reference

`Vendors::Postgate::Client` (`app/services/vendors/postgate/client.rb`) is raw HTTP only — no
domain logic, no DB writes, no post-aware orchestration. It raises the shared
`Vendors::Base` error hierarchy (`AuthenticationError` on 401/403, `RateLimitError` on 429,
`ServerError` on 5xx, `NotConfiguredError` when `postgate.api_key` is blank) so callers can
`rescue` uniformly across every vendor.

| Method | Endpoint |
|---|---|
| `create_profile_group(name:, timezone:)` | `POST /api/profile-groups` |
| `list_profile_groups` | `GET /api/profile-groups` |
| `delete_profile_group(id)` | `DELETE /api/profile-groups/{id}` |
| `create_connect_url(platform:, profile_group_id:, return_url:, instance_url:)` | `POST /api/profiles/connect` |
| `list_profiles(**filters)` | `GET /api/profiles` |
| `get_profile(id)` | `GET /api/profiles/{id}` |
| `delete_profile(id)` | `DELETE /api/profiles/{id}` |
| `profile_health(id)` | `GET /api/profiles/{id}/health` |
| `profile_stats(id, from:, to:)` | `GET /api/profiles/{id}/stats` |
| `import_profile_posts(id)` | `POST /api/profiles/{id}/import` |
| `list_boards(profile_id)` | `GET /api/profiles/{id}/boards` |
| `create_post(payload, idempotency_key:)` | `POST /api/posts` |
| `get_post(id)` | `GET /api/posts/{id}` |
| `delete_post(id)` | `DELETE /api/posts/{id}` |
| `post_logs(id)` | `GET /api/posts/{id}/logs` |
| `post_stats(post_ids:, from:, to:)` | `GET /api/posts/stats` |
| `live_stats(post_id)` | `GET /api/posts/{id}/live-stats` |
| `analytics_timeseries(from:, to:, platform:, profile_id:, profile_group_id:, compare:)` | `GET /api/analytics/timeseries` |
| `platforms` | `GET /api/platforms` |
| `quotas` | `GET /api/quotas` |
| `connect_origins` | `GET /api/connect-origins` |
| `allow_connect_origin(origin:, label:)` | `POST /api/connect-origins` |
| `list_webhooks` | `GET /api/webhooks` |
| `create_webhook(url:, events:)` | `POST /api/webhooks` |
| `delete_webhook(id)` | `DELETE /api/webhooks/{id}` |

Every method returns the parsed JSON body (a `Hash`/`Array`, string keys). Nil keyword args are
dropped from the request payload rather than sent as `null`.

## 7. Gotchas & testing checklist

- **`sandbox` platform never publishes anywhere real** — use a PostGate test API key + the
  `sandbox` platform end-to-end in dev/CI before touching a real network.
- **`Idempotency-Key` on every `create_post` call** — without it a network blip on the agencios
  side (timeout on our end after PostGate already accepted the post) turns into a duplicate
  publish. Reuse the same key across retries of the same logical attempt.
- **Publishing is never synchronous** — the `201` from `POST /api/posts` only means "accepted",
  not "live". Never treat it as a publish confirmation; wait for `post.published` /
  `post.partial` / `post.failed`.
- **`return_url` origin must be pre-registered** (`POST /api/connect-origins`) *before* the first
  `create_connect_url` call in a new environment, or the hosted flow has nowhere valid to
  redirect back to.
- **Mastodon needs `instance_url` at connect time** — there is no way to add it after the fact;
  the hosted flow fails without it.
- **Pinterest boards are read live, not cached** — call `list_boards` close to when the picker is
  rendered; a stale board id from days ago may 404 if the user renamed/deleted it.
- **Webhook secret is shown once** — capture it at `create_webhook` time; if lost, delete and
  recreate the webhook rather than trying to recover it.
- **`analytics` plan feature gates both `/api/analytics/timeseries` and `/api/posts/{id}/live-stats`**
  — check `GET /api/quotas` before building UI that assumes they're always available.
