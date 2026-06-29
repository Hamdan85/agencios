# Upload-Post — Multi-Network Posting Aggregator (the fallback / fast-path for `agencios`)

> Researched against the official docs (`docs.upload-post.com`) and site (`upload-post.com`), 2025–2026. Cited inline. Upload-Post is **one API that posts to 10+ social networks** and handles each network's OAuth for you.

---

## 0. When to use this vs direct integrations (decision guidance)

`agencios` should treat Upload-Post as the **fast-path / fallback**, and direct per-network integrations (e.g. `x-twitter.md`) as the deep path. They are not mutually exclusive — pick per network.

**Use Upload-Post (aggregator) when:**
- You want **one integration** instead of N OAuth flows, N media pipelines, N rate-limit dialects.
- You need **breadth fast** — ship TikTok, Instagram, YouTube, LinkedIn, Facebook, X, Threads, Pinterest, Reddit, Bluesky, Discord, Telegram in days, not quarters.
- You don't want to **own each platform's app review** (TikTok/Meta/LinkedIn app approvals are slow and political). Upload-Post connects users through *their* verified apps.
- Per-network analytics depth is "nice to have," not the core product.

**Use direct integration when:**
- A network is **strategic** and you need full control / the freshest features / deepest metrics (this is the argument for the direct X build).
- You want to **avoid per-upload cost and third-party dependency** for your highest-volume network.
- Compliance/data-residency requires you to hold the tokens yourself.

**Trade-offs (be honest):**

| | Aggregator (Upload-Post) | Direct per-network |
|---|---|---|
| Time to ship | Days | Weeks–months per network |
| Auth burden | They handle it (connect links) | You build + maintain each OAuth |
| App review | Their apps | Your apps (slow approvals) |
| Cost | **Per-upload / plan cost** on top of your own infra | Network's own API cost (e.g. X pay-as-you-go) |
| Control / features | Lowest-common-denominator; lag on new features | Full |
| Analytics depth | Unified but shallower schema | As deep as the network allows |
| Dependency / ToS risk | Single point of failure; their ToS standing with each network is a risk you inherit | You own the risk directly |

**Recommended posture for `agencios`:** default everything through Upload-Post via a common `SocialPublisher` interface; selectively swap individual networks (starting with X) to a direct `Vendors::X` implementation when volume/feature needs justify it.

---

## 1. Sign up + get API key (clickpath)

1. Go to **`upload-post.com`** → **Sign up** (free tier, no credit card — 10 uploads/month, 2 profiles). ([upload-post.com](https://www.upload-post.com/), [docs landing](https://docs.upload-post.com/landing/))
2. Open the **dashboard** → **API Keys** (Settings) → **Generate / copy your API key**.
3. All API requests authenticate with that key in the header:
   ```
   Authorization: Apikey YOUR_API_KEY
   ```
   (Note the literal word **`Apikey`** as the scheme, not `Bearer`.) ([docs](https://docs.upload-post.com/))
4. Store the key in **Rails encrypted credentials** (`upload_post.api_key`) — never `.env`, never the repo.

**Base URL:** `https://api.upload-post.com/api`

---

## 2. How their auth / connection model works (profiles + JWT connect links)

Upload-Post is **white-label / multi-tenant by design**, which maps cleanly onto `agencios` workspaces. You never handle each social network's OAuth yourself — Upload-Post hosts a connect page and stores the tokens. ([user profiles docs](https://docs.upload-post.com/api/user-profiles/))

The model has two layers:
- **Your account / API key** — your relationship with Upload-Post (billing, quota).
- **Profiles (`user`)** — one per end-user/client/workspace. Each profile has its own set of connected social accounts.

### Flow

1. **Create a profile** for each `agencios` workspace (or per client):
   ```
   POST /api/uploadposts/users
   { "username": "workspace_<id>" }     // your stable identifier
   ```
   Response includes `created_at`, `social_accounts` (empty at first), `success`.

2. **Generate a JWT connect link** so the user can link their social accounts:
   ```
   POST /api/uploadposts/users/generate-jwt
   {
     "username": "workspace_<id>",
     "redirect_url": "https://app.agencios.com/integrations/upload-post/callback",
     "logo_image": "https://app.agencios.com/logo.png",
     "platforms": ["instagram", "tiktok", "x", "linkedin"],
     "show_calendar": true
   }
   ```
   Response:
   ```json
   { "access_url": "https://app.upload-post.com/connect?token=JWT_TOKEN",
     "duration": "48h", "success": true }
   ```

3. **Redirect the user** to `access_url`. They authenticate with each platform via OAuth on Upload-Post's hosted page (Upload-Post stores the tokens), then get bounced back to your `redirect_url`. JWT is valid ~48h, single-use.

4. **(Optional) Validate** a token before redirect: `POST /api/uploadposts/users/validate-jwt` with `Authorization: Bearer JWT_TOKEN`.

5. **Read connected accounts:**
   ```
   GET /api/uploadposts/users/{username}
   ```
   Returns `profile.social_accounts` with per-platform `display_name`, `username`, `social_images` (and `null` for unlinked platforms).

White-label extras: custom `logo_image` / `connect_title` / `connect_description`; restrict platforms via the `platforms` array; `readonly_calendar` for a non-editable calendar view; Discord webhooks / Telegram bots use direct credential submission instead of OAuth.

---

## 3. API: upload photo / video / text (endpoints + payloads + platforms)

All endpoints are **`multipart/form-data`**, header `Authorization: Apikey YOUR_API_KEY`. Arrays use the `platform[]` / `photos[]` form-key convention. ([docs](https://docs.upload-post.com/))

### Text post
```
POST /api/upload_text
```
| Param | Notes |
|---|---|
| `user` (req) | profile identifier |
| `platform[]` (req) | `x`, `linkedin`, `facebook`, `threads`, `reddit`, `bluesky`, `discord`, `telegram`, `google_business` |
| `title` (req) | the post text |
| `scheduled_date`, `timezone`, `async_upload`, `first_comment` | optional |
| Platform-specific | X: `reply_to_id`, `poll_options`, `quote_tweet_id` · Reddit: `subreddit`, `flair_id`, `reddit_link_url` · Facebook: `facebook_page_id`, `facebook_link_url` · LinkedIn: `target_linkedin_page_id`, `linkedin_link_url` · Threads: `threads_topic_tag`, `threads_long_text_as_post` |

```bash
curl -H 'Authorization: Apikey YOUR_API_KEY' \
  -F 'user=workspace_42' -F 'platform[]=x' \
  -F 'title=This is my tweet content!' \
  -X POST https://api.upload-post.com/api/upload_text
```
Sync response:
```json
{ "success": true,
  "results": { "x": { "success": true, "url": "https://x.com/..." } },
  "usage": { "count": 14, "limit": 100 } }
```

### Photo post
```
POST /api/upload_photos
```
Platforms: TikTok, Instagram, LinkedIn, Facebook, X, Threads, Pinterest, Bluesky, Reddit, Discord, Telegram.
Key params: `user` (req), `platform[]` (req), `photos[]` (req, image files), `title` (required for Reddit), `description`, `scheduled_date`, `first_comment`.

### Video post
```
POST /api/upload
```
Platforms: TikTok, Instagram, LinkedIn, YouTube, Facebook, X, Threads, Pinterest, Bluesky, Discord, Telegram.
Key params: `user` (req), `platform[]` (req), `video` (req, file), `title`, `scheduled_date`, `async_upload`, `add_to_queue`. Upload-Post auto-transcodes/crops per destination.

### Async & status
For large videos set `async_upload=true`; poll:
```
GET /api/uploadposts/status?request_id=<id>     # async uploads
GET /api/uploadposts/status?job_id=<id>         # scheduled posts
```
History / scheduling: `GET /api/uploadposts/history`, `GET /api/uploadposts/schedule`, `PATCH|DELETE /api/uploadposts/schedule/{job_id}`.

### Supported platforms (full)
TikTok, Instagram, YouTube, Facebook, LinkedIn, X/Twitter, Threads, Pinterest, Reddit, Bluesky, Discord, Telegram (+ Google Business). ([upload-post.com](https://www.upload-post.com/))

---

## 4. Analytics: what they expose

Upload-Post offers a **unified analytics schema** across networks — more than most aggregators, but still shallower than going direct. ([docs](https://docs.upload-post.com/))

| Endpoint | Returns |
|---|---|
| `GET /api/analytics/{profile_username}?platforms=instagram,x,...` | Profile-level analytics across platforms (`page_id` for FB, `page_urn` for LinkedIn) |
| `GET /api/uploadposts/total-impressions/{profile_username}` | Aggregated impressions; `date` / `start_date`+`end_date` / `period` (`last_day`…`last_year`), `platform`, `breakdown`, `metrics` |
| `GET /api/uploadposts/post-analytics/{request_id}` | Per-post metrics for an upload you made (optionally `platform`) |
| `GET /api/uploadposts/post-analytics?platform_post_id=&platform=&user=` | Per-post metrics by native post id |
| `GET /api/uploadposts/platform-metrics` | Which metrics each platform supports |
| `GET /api/uploadposts/media` | A profile's media on a platform |
| `GET /api/uploadposts/comments` | Post comments (pagination via `after`) |

Also available: comment replies (`/comments/reply`, `/comments/public-reply`), DMs (`/dms/send`, `/dms/conversations`), AutoDM monitors, and an FFmpeg editor endpoint. Treat these as bonus surface — for `agencios` the core is publish + impressions/post-analytics.

**Caveat:** analytics depth is bounded by what each network exposes through Upload-Post and is normalized to their schema. If you need X's owner-only `non_public_metrics`/`organic_metrics` or fine-grained breakdowns, that's the case for a direct integration on that network.

---

## 5. Pricing model → maps to `agencios` usage-based billing

Plans (verify on the [pricing page](https://www.upload-post.com/) — they change):

| Plan | Price | Profiles | Uploads |
|---|---|---|---|
| **Free** | $0 | 2 | 10/month |
| **Basic** | ~$16/mo (annual) | ~5 | unlimited uploads + API access |
| (mid-tier) | ~$18/mo | ~5 | — |
| Higher tiers | scaling | more profiles | + bigger FFmpeg quota |

Sources: [upload-post.com](https://www.upload-post.com/), [linkstartai review](https://www.linkstartai.com/en/agents/upload-post), site search results. They position as cheaper than Ayrshare ($49+/mo).

Billing primitives that matter:
- **Quota is "uploads"** (each `upload`/`upload_photos`/`upload_text` call counts; the API returns `usage: { count, limit }`). FFmpeg has its own monthly minute quota.
- **Profiles** ≈ connected end-users/workspaces (plan-capped).

**Mapping to `agencios` usage-based billing:**
- Map **Upload-Post "uploads" → billable publish events** per workspace. Read `usage.count`/`usage.limit` from every response and record it against the workspace; this is your cost-of-goods to mark up.
- Map **Upload-Post "profiles" → `agencios` workspaces** (or per-client sub-profiles). If a client needs more connected channels, that's a plan dimension to pass through.
- Because Upload-Post is **flat-rate-with-caps** (not strictly per-upload above Basic), model `agencios` margin as: (your subscription tier cost) ÷ (expected workspace publishes) → per-publish unit cost, then mark up. For X **direct**, your COGS is X's pay-as-you-go (~$0.015/post, ~$0.20/post-with-link) instead — your `SocialPublisher` should attribute cost per network so billing reflects which path served the post.
- Track quota headroom; when a workspace approaches the plan's upload/profile cap, that's an upgrade trigger in `agencios` billing.

---

## 6. Backend plan for `agencios`

### Vendor wrapper — `Vendors::UploadPost`

```
app/services/vendors/upload_post/
  client.rb                      # HTTP: base https://api.upload-post.com/api, header "Authorization: Apikey <key>"
  actions/
    create_profile.rb            # POST /uploadposts/users
    generate_connect_link.rb     # POST /uploadposts/users/generate-jwt  -> access_url
    validate_jwt.rb              # POST /uploadposts/users/validate-jwt
    fetch_profile.rb             # GET  /uploadposts/users/{username}     -> connected accounts
    upload_text.rb               # POST /upload_text
    upload_photos.rb             # POST /upload_photos
    upload_video.rb              # POST /upload
    fetch_upload_status.rb       # GET  /uploadposts/status
    fetch_post_analytics.rb      # GET  /uploadposts/post-analytics...
    fetch_profile_analytics.rb   # GET  /analytics/{username}
```

`Vendors::UploadPost::Client` reads `Rails.application.credentials.dig(:upload_post, :api_key)`, sets the `Apikey` header, and exposes low-level `post_multipart` / `get`. Actions follow the house `.call` convention and delegate to the client.

### `SocialAccount` with `provider: :upload_post`

Reuse the same `SocialAccount` model from `x-twitter.md` (`belongs_to :workspace`, encrypted token columns). For Upload-Post there's **no OAuth token to store** (they hold it) — instead store **their profile reference**:

```ruby
SocialAccount.create!(
  workspace: workspace,
  provider: :upload_post,
  external_account_id: "workspace_#{workspace.id}",  # the Upload-Post profile `username`
  metadata: { connected_platforms: ["x", "instagram"], connect_url: access_url }
)
```
- `external_account_id` = the Upload-Post **profile username**.
- `access_token`/`refresh_token` stay null for this provider (encrypted columns just go unused).
- `metadata` caches which platforms are connected (refreshed from `FetchProfile`).

A workspace can hold **both** a `provider: :upload_post` row *and* a `provider: :x` row — the `SocialPublisher` picks which to use per network.

### Common `SocialPublisher` interface (swap direct vs aggregator per network)

```ruby
# app/services/publishing/social_publisher.rb
module Publishing
  class SocialPublisher
    # Routes a publish request for one network to the configured backend.
    ROUTES = {
      "x"        => :direct,        # use Vendors::X directly
      "instagram"=> :upload_post,   # via aggregator
      "tiktok"   => :upload_post,
      # ...
    }.freeze

    def self.for(network:, workspace:)
      case ROUTES.fetch(network, :upload_post)
      when :direct      then Direct::X.new(workspace)          # wraps Operations::Publishing::PublishToX
      when :upload_post then Aggregated::UploadPost.new(workspace, network)
      end
    end
  end
end
```

- Each backend implements the same verbs: `publish_text`, `publish_photos`, `publish_video`, `fetch_metrics`.
- `Aggregated::UploadPost` → calls `Vendors::UploadPost::Actions::*`.
- `Direct::X` → calls `Operations::Publishing::PublishToX` (which uses `Vendors::X::Actions::*`).
- Flipping a network from aggregator to direct is a **one-line change in `ROUTES`** (or a per-workspace override column) — no caller changes. This is the whole point: ship fast on Upload-Post, graduate strategic networks to direct without rewriting publish logic.

### Operations + jobs
- `Operations::Publishing::Publish` — fans a multi-network request out to `SocialPublisher.for(...)` per network, aggregates results.
- `PublishViaUploadPostJob` (Sidekiq) — async dispatch; for `async_upload=true` videos, enqueue a poller hitting `FetchUploadStatus`.
- `SyncUploadPostAnalyticsJob` (scheduled) — pulls `FetchPostAnalytics`/`FetchProfileAnalytics`, records `usage.count`/`usage.limit` for billing.
- Connect flow controller action calls `Vendors::UploadPost::Actions::GenerateConnectLink` and redirects to `access_url`; the callback re-syncs `FetchProfile`.

---

## 7. Gotchas & testing checklist

**Gotchas**
- Auth scheme is **`Authorization: Apikey <key>`** (not `Bearer`). Easy 401 if you copy a Bearer snippet.
- Endpoints are **`multipart/form-data`** with `platform[]` / `photos[]` array keys — not JSON. JSON bodies will be rejected.
- **Connect JWT is ~48h and single-use** — generate on demand, don't cache/share.
- **Reddit needs `title`** (and usually `subreddit`); X-specific options (`reply_to_id`, `quote_tweet_id`, `poll_options`) ride on the same endpoints.
- **Per-platform results are independent**: the response `results` map can have one platform succeed and another fail in the same call — check each, don't treat the top-level `success` as all-or-nothing.
- **Quota is real**: Free = 10 uploads/mo, 2 profiles. Hitting the cap fails publishes — surface `usage` to the workspace.
- **Dependency risk**: Upload-Post sits between you and the networks; their outage = your outage, and their ToS standing with each network is a risk you inherit. Keep the `SocialPublisher` seam so you can route around it.
- **Discord/Telegram** use direct webhook/bot credentials, not OAuth — different connect path.
- **Analytics depth is normalized/shallower** than direct; don't promise X owner-only metrics through the aggregator.

**Testing checklist**
- [ ] API key in Rails credentials; `Client` sends `Apikey` header; a `GET /uploadposts/me` (current user) succeeds.
- [ ] `CreateProfile` creates a profile keyed to `workspace_<id>`.
- [ ] `GenerateConnectLink` returns an `access_url`; opening it shows the branded connect page; after linking, `FetchProfile` shows the account.
- [ ] `SocialAccount(provider: :upload_post)` row created with the profile username + connected-platforms metadata.
- [ ] `upload_text` to `x` returns `results.x.success` and a post URL.
- [ ] `upload_photos` (multi-image) and `upload` (video, `async_upload=true` → poll `status`) succeed.
- [ ] Multi-platform call where one platform is unlinked → partial-failure handling verified.
- [ ] `usage.count`/`usage.limit` recorded per publish for billing.
- [ ] Analytics: `post-analytics` and `analytics/{username}` return data; `SyncUploadPostAnalyticsJob` persists it.
- [ ] `SocialPublisher` routes `x` → direct and `instagram` → upload_post; flipping `ROUTES` reroutes with no caller change.

---

**Doc sources:** [docs.upload-post.com](https://docs.upload-post.com/) · [user profiles](https://docs.upload-post.com/api/user-profiles/) · [upload_text](http://docs.upload-post.com/api/upload-text/) · [docs landing](https://docs.upload-post.com/landing/) · [upload-post.com (pricing/platforms)](https://www.upload-post.com/) · [linkstartai review](https://www.linkstartai.com/en/agents/upload-post)
