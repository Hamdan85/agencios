# Meta Integration Guide — Instagram + Facebook (agencios)

> Current as of June 2026. Graph API **v25.0** is the latest (released 2026-02-18); v23.0/v24.0 are
> still active. Pin the version in `Vendors::Meta::Client` (`META_GRAPH_VERSION = "v25.0"`).
>
> Primary refs:
> - https://developers.facebook.com/docs/instagram-platform/content-publishing/
> - https://developers.facebook.com/docs/instagram-platform/api-reference/instagram-user/insights/
> - https://developers.facebook.com/docs/pages-api/posts/
> - https://developers.facebook.com/docs/video-api/guides/publishing/
> - https://developers.facebook.com/docs/graph-api/changelog

---

## 0. What you'll build

One **Meta app** powers both Instagram and Facebook publishing. A workspace connects an
**Instagram Professional account** (linked to a Facebook Page) and/or a **Facebook Page** via a
single Facebook Login OAuth flow. Publishing uses the 2-step *create container → publish* pattern
for Instagram and direct Page posting for Facebook. Analytics reads account/page-level metrics and
per-post/media insights.

All Graph calls live in `Vendors::Meta::Client` with one `Vendors::Meta::Actions::*` class per
call. Orchestration is `Operations::Meta::*` and `Operations::Instagram::*` /
`Operations::Facebook::*`, run by Sidekiq jobs. Credentials: app-level keys in Rails encrypted
credentials; per-workspace tokens encrypted on `SocialAccount`.

---

## 1. Accounts & prerequisites

1. **Meta Business Portfolio (Business Manager)** at https://business.facebook.com — the app,
   Pages, and IG accounts must live under it for Advanced Access.
2. **A Facebook Page** owned by that business; the connecting user must hold `CREATE_CONTENT` +
   `MANAGE` task roles.
3. **An Instagram Professional account** (Business recommended; Creator also works since 2025).
   The IG account must be **linked to the Facebook Page** (IG app → Settings → Account → Sharing
   to other apps, or Page → Linked accounts → Instagram).
4. **Business Verification** of the portfolio — required for Advanced Access to
   `instagram_content_publish` and `pages_manage_posts`.
5. **A public HTTPS callback domain** for OAuth redirect + webhooks (ngrok for dev).
6. **≥100 Page likes** for most Page Insights; **≥100 followers** for some IG demographics.

---

## 2. Create the Meta app (one app, both networks)

> Drive this clickpath in the Claude Chrome extension. Log in to the Facebook account that admins
> the Business Portfolio first.

1. Go to **https://developers.facebook.com/apps** → **Create app** (top right).
2. **App details**: name `agencios`, contact email → **Next**.
3. **Use case**: select **"Other"** → **Next** (or "Manage everything on your Page").
4. **App type**: **Business** → **Next** → **Create app** (re-enter password if asked).
5. App Dashboard → **App settings → Basic**. Copy **App ID** + **App secret** (click *Show*).
6. In the left rail, **Add products**:
   - **Facebook Login for Business** → **Set up**
   - **Instagram** → **Set up** (Instagram Graph API / "Instagram API setup with Facebook Login")
   - **Webhooks** (optional — §8)
7. **Facebook Login → Settings**: add **Valid OAuth Redirect URIs**:
   `https://app.agencios.example/oauth/meta/callback` + ngrok URL. Save.
8. **App settings → Basic**: set App Domains, Privacy Policy URL, Terms URL, Category; complete
   **Business Verification**.
9. Flip **Development → Live** only after App Review is approved.

---

## 3. Permissions & scopes

Request all relevant scopes in one OAuth call (the user grants what they have). You can merge
Instagram and Facebook scopes because one login handles both.

### 3a. Instagram scopes

| Scope | Why | Access level |
|---|---|---|
| `instagram_basic` | Read IG account id, media, basic fields | **Advanced** (App Review) |
| `instagram_content_publish` | Publish images/carousels/Reels | **Advanced + Business Verification** |
| `instagram_manage_insights` | Account + media insights | **Advanced** (App Review) |

### 3b. Facebook Page scopes

| Scope | Why | Access level |
|---|---|---|
| `pages_show_list` | List Pages the user manages | **Advanced** (App Review) |
| `pages_read_engagement` | Read Page content/metadata and resolve IG link | **Advanced** |
| `pages_manage_posts` | Create/edit/delete Page posts, photos, videos, Reels | **Advanced + Business Verification** |
| `pages_read_user_content` | Read comments/UGC on the Page | **Advanced** |
| `read_insights` | Page + post insights | **Advanced** (App Review) |
| `business_management` | Resolve assets via the Business Portfolio | **Advanced** |
| `public_profile` | Default | Standard |

**App Review rules:**
- **Standard Access** = works only for users with a role on the app/business — fine for building.
- **Advanced Access** = required to serve accounts you don't own. Each permission is submitted
  separately with a **written use-case + screencast** of the full user flow. Approval ~2–7 days.
- `instagram_content_publish` and `pages_manage_posts` both require **Business Verification**.

---

## 4. OAuth flow (single login for both IG and Facebook)

Base: `https://graph.facebook.com/v25.0`. One OAuth pass yields both the Page token (Facebook
publishing + insights) and the `instagram_business_account.id` (IG publishing + insights).

### Step 1 — Authorize dialog (browser redirect)

```
GET https://www.facebook.com/v25.0/dialog/oauth
  ?client_id={APP_ID}
  &redirect_uri=https://app.agencios.example/oauth/meta/callback
  &state={CSRF_TOKEN}
  &scope=instagram_basic,instagram_content_publish,instagram_manage_insights,
         pages_show_list,pages_read_engagement,pages_manage_posts,read_insights,business_management
  &response_type=code
```
→ `Vendors::Meta::Actions::AuthorizeUrl`

> **Facebook Login for Business (Business apps).** A Business-type app uses
> **Facebook Login for Business**, where a dashboard-created **configuration**
> replaces `scope`. Create it at **App Dashboard → Facebook Login for Business →
> Configurations** (pick the permissions in §3 + the assets the business grants),
> copy the **Configuration ID**, and set it in credentials as
> `meta.fb_login_config_id` (env `META_FB_LOGIN_CONFIG_ID`). When present,
> `AuthorizeUrl` sends `config_id=...` **instead of** `scope`; absent, it falls
> back to the classic scope-based dialog above. The code→token exchange (Step 2)
> is identical either way.

### Step 2 — Exchange `code` for a short-lived user token (on callback)

```
GET /v25.0/oauth/access_token
  ?client_id={APP_ID}
  &client_secret={APP_SECRET}
  &redirect_uri={SAME_REDIRECT_URI}
  &code={CODE}
```
→ `Vendors::Meta::Actions::ExchangeCodeForToken`

### Step 3 — Short-lived → long-lived user token (~60 days)

```
GET /v25.0/oauth/access_token
  ?grant_type=fb_exchange_token
  &client_id={APP_ID}
  &client_secret={APP_SECRET}
  &fb_exchange_token={SHORT_LIVED_TOKEN}
→ { access_token, expires_in }
```
→ `Vendors::Meta::Actions::ExchangeLongLivedToken`

### Step 4 — List Pages + non-expiring Page token + linked IG account id

```
GET /v25.0/me/accounts
  ?fields=id,name,access_token,tasks,instagram_business_account{id,username}
  &access_token={LONG_LIVED_USER_TOKEN}
```
Each entry has the Page `id`, a **non-expiring Page `access_token`**, `tasks` (must include
`CREATE_CONTENT` for FB posting), and `instagram_business_account.id` (the IG account id used for
all IG API calls). → `Vendors::Meta::Actions::ListPages`

Orchestrate Steps 2–4 in `Operations::Meta::ConnectAccount`; persist both `instagram` and
`facebook` `SocialAccount` rows (same user token, separate rows with different `provider`).

> **Token refresh:** long-lived **user** tokens last ~60 days. Refresh by repeating Step 3 with
> the current long-lived token before day 60. Page tokens derived from a fresh user token are
> effectively permanent. Store `token_expires_at`; refresh at ~day 50 via `Meta::RefreshTokenJob`
> → `Operations::Meta::RefreshLongLivedToken`.

---

## 5. Store credentials

### 5a. Rails encrypted credentials

```yaml
meta:
  app_id:               "1234567890"
  app_secret:           "xxxxxxxxxxxxxxxx"
  webhook_verify_token: "a-random-string-you-pick"   # §8
  graph_version:        "v25.0"
```

Read via `Rails.application.credentials.dig(:meta, :app_id)`.

### 5b. `SocialAccount` model

One row per connected account per workspace. `provider` is `"instagram"` or `"facebook"`.
Both rows are created from the same OAuth pass.

```ruby
create_table :social_accounts do |t|
  t.references :workspace, null: false, foreign_key: true
  t.string  :provider, null: false              # "instagram" | "facebook" | ...
  t.string  :external_user_id                   # FB app-scoped user id (me.id)
  t.string  :page_id                            # linked FB Page id
  t.string  :page_name                          # display
  t.string  :ig_user_id                         # instagram_business_account.id (IG publish target)
  t.string  :username                           # IG @handle or Page name
  t.text    :user_access_token                  # encrypted: long-lived USER token
  t.text    :page_access_token                  # encrypted: non-expiring PAGE token  <-- used for all publish + insights
  t.datetime :token_expires_at                  # user token expiry (~60d)
  t.jsonb   :scopes, default: []                # granted scopes (audit)
  t.string  :status, null: false, default: "connected"  # connected | needs_reauth | revoked
  t.datetime :last_synced_at
  t.timestamps
end

add_index :social_accounts, [:workspace_id, :provider], unique: false
```

```ruby
class SocialAccount < ApplicationRecord
  belongs_to :workspace
  encrypts :user_access_token
  encrypts :page_access_token
end
```

`Vendors::Meta::Client.new(social_account)` reads `page_access_token` (all publish + insights
calls use the **Page token**) and the appropriate id (`ig_user_id` for IG, `page_id` for FB).

---

## 6. Publishing

Base: `https://graph.facebook.com/v25.0`. Auth: **Page access token** for all calls.

Media URLs supplied to the API must be **publicly reachable HTTPS** at publish time — host on S3/
ActiveStorage public URLs. Container expiry is **24 hours** for IG; publish within that window.

---

### 6a. Instagram publishing

Pattern: always **create container(s) → (poll status for video) → publish**.

#### 6a.1 Single image

```
POST /v25.0/{IG_USER_ID}/media
  image_url=https://cdn.agencios.example/post.jpg
  caption=Your caption #hashtags
  alt_text=Accessible description           # optional
  access_token={PAGE_TOKEN}
→ { "id": "<CREATION_ID>" }
```

```
POST /v25.0/{IG_USER_ID}/media_publish
  creation_id=<CREATION_ID>
  access_token={PAGE_TOKEN}
→ { "id": "<MEDIA_ID>" }
```
→ `Vendors::Meta::Actions::CreateMediaContainer` + `Vendors::Meta::Actions::PublishMedia`

#### 6a.2 Carousel (2–10 items)

1. Create each **child** container:
```
POST /v25.0/{IG_USER_ID}/media
  image_url=...   (or video_url=... & media_type=VIDEO)
  is_carousel_item=true
  access_token={PAGE_TOKEN}
→ { "id": "<CHILD_ID>" }    # repeat per slide
```
2. Create the **parent carousel** container:
```
POST /v25.0/{IG_USER_ID}/media
  media_type=CAROUSEL
  children=<CHILD_ID_1>,<CHILD_ID_2>,...
  caption=...
  access_token={PAGE_TOKEN}
→ { "id": "<CREATION_ID>" }
```
3. Publish with `media_publish` + `creation_id` (same as 6a.1).

→ `Vendors::Meta::Actions::CreateCarouselItem` → `CreateCarouselContainer` → `PublishMedia`

#### 6a.3 Reels / video

**Mode A — hosted URL:**
```
POST /v25.0/{IG_USER_ID}/media
  media_type=REELS
  video_url=https://cdn.agencios.example/reel.mp4
  caption=...
  share_to_feed=true
  access_token={PAGE_TOKEN}
→ { "id": "<CREATION_ID>" }
```

**Mode B — resumable upload (large/local files):**
```
POST /v25.0/{IG_USER_ID}/media
  media_type=REELS
  upload_type=resumable
  caption=...
  access_token={PAGE_TOKEN}
→ { "id": "<CREATION_ID>", "uri": "<UPLOAD_URI>" }

POST https://rupload.facebook.com/ig-api-upload/v25.0/{CREATION_ID}
  Authorization: OAuth {PAGE_TOKEN}
  offset: 0
  file_size: {BYTES}
  <raw video bytes>
```
→ `Vendors::Meta::Actions::CreateReelsContainer` + `Vendors::Meta::Actions::UploadResumableVideo`

**Poll until `status_code=FINISHED` before publishing** (video processing is async):
```
GET /v25.0/{CREATION_ID}?fields=status_code,status&access_token={PAGE_TOKEN}
→ status_code ∈ { IN_PROGRESS | FINISHED | ERROR | EXPIRED | PUBLISHED }
```
→ `Vendors::Meta::Actions::GetContainerStatus` — loop with backoff (5s → 30s).

**Check publishing quota before every publish:**
```
GET /v25.0/{IG_USER_ID}/content_publishing_limit
  ?fields=config,quota_usage
  &access_token={PAGE_TOKEN}
```
Error code **9** = limit hit. Carousels count as one post.
→ `Vendors::Meta::Actions::GetPublishingLimit`

#### 6a.4 Orchestration

`Operations::Instagram::PublishPost` owns the whole dance:
1. Check `GetPublishingLimit` — fail fast if at cap.
2. Build container(s) via the right `Actions::Create*Container`.
3. For video/Reels, poll `GetContainerStatus` until `FINISHED` (fail on `ERROR`/`EXPIRED`).
4. Call `PublishMedia`; save the returned `MEDIA_ID` to the `Post` record.

Run from `Instagram::PublishPostJob` (Sidekiq, `default` queue). For Reels, either poll with
back-off inside the job or split into `Instagram::PollContainerJob` that re-enqueues itself.

---

### 6b. Facebook publishing

Pattern: direct `feed`/`photos`/`videos` POST; video and Reels are async (poll or finish-and-publish).

#### 6b.1 Text / link post

```
POST /v25.0/{PAGE_ID}/feed
  message=Hello world
  link=https://agencios.example              # optional — FB renders a link preview
  published=true
  access_token={PAGE_TOKEN}
→ { "id": "{PAGE_ID}_{POST_ID}" }
```

**Scheduled:** `published=false` + `scheduled_publish_time={unix}` (10 min – 30 days out).
→ `Vendors::Meta::Actions::CreateFeedPost`

#### 6b.2 Single photo

```
POST /v25.0/{PAGE_ID}/photos
  url=https://cdn.agencios.example/photo.jpg     # or `source` = multipart file upload
  caption=Caption text
  published=true
  access_token={PAGE_TOKEN}
→ { "id": "<PHOTO_ID>", "post_id": "<POST_ID>" }
```
→ `Vendors::Meta::Actions::CreatePagePhoto`

#### 6b.3 Multi-photo post (2-step)

1. Upload each photo **unpublished** to get a media id:
```
POST /v25.0/{PAGE_ID}/photos
  url=...
  published=false
  access_token={PAGE_TOKEN}
→ { "id": "<MEDIA_FBID>" }    # repeat per photo
```
2. Create the feed post with attached_media:
```
POST /v25.0/{PAGE_ID}/feed
  message=Gallery caption
  attached_media[0]={"media_fbid":"<MEDIA_FBID_1>"}
  attached_media[1]={"media_fbid":"<MEDIA_FBID_2>"}
  access_token={PAGE_TOKEN}
```
→ `CreatePagePhoto` (published=false) × N → `CreateFeedPost` (with `attached_media`)

#### 6b.4 Video — 3-phase resumable upload

**Phase 1 — START:**
```
POST /v25.0/{PAGE_ID}/videos
  upload_phase=start
  file_size={BYTES}
  access_token={PAGE_TOKEN}
→ { "video_id": "<VIDEO_ID>", "upload_session_id": "<SESSION>", "start_offset": "0", "end_offset": "<N>" }
```
**Phase 2 — TRANSFER** (loop chunks until `start_offset == end_offset`):
```
POST /v25.0/{PAGE_ID}/videos
  upload_phase=transfer
  upload_session_id=<SESSION>
  start_offset=<current>
  video_file_chunk=@<chunk bytes>    # multipart
  access_token={PAGE_TOKEN}
→ { "start_offset": "<next>", "end_offset": "<N>" }
```
**Phase 3 — FINISH:**
```
POST /v25.0/{PAGE_ID}/videos
  upload_phase=finish
  upload_session_id=<SESSION>
  title=...  description=...
  access_token={PAGE_TOKEN}
→ { "success": true }
```
Poll:
```
GET /v25.0/{VIDEO_ID}?fields=status&access_token={PAGE_TOKEN}
→ status.video_status ∈ { processing | ready | error }
```
→ `Actions::StartVideoUpload` + `TransferVideoChunk` + `FinishVideoUpload` + `GetVideoStatus`

#### 6b.5 Facebook Reels (chunked `video_reels`)

```
POST /v25.0/{PAGE_ID}/video_reels
  upload_phase=start
  access_token={PAGE_TOKEN}
→ { "video_id": "<VIDEO_ID>", "upload_url": "https://rupload.facebook.com/video-upload/v25.0/<VIDEO_ID>" }

POST https://rupload.facebook.com/video-upload/v25.0/{VIDEO_ID}
  Authorization: OAuth {PAGE_TOKEN}
  offset: 0 / file_size: {BYTES}
  <raw video bytes>     # OR header `file_url: https://cdn.../reel.mp4`
→ { "success": true }
```

Poll `status` through phases: `uploading_phase → processing_phase → publishing_phase`, then finish:
```
POST /v25.0/{PAGE_ID}/video_reels
  video_id=<VIDEO_ID>
  upload_phase=finish
  video_state=PUBLISHED            # or DRAFT | SCHEDULED (+ scheduled_publish_time)
  description=Caption #hashtags
  access_token={PAGE_TOKEN}
```
→ `Actions::StartReelUpload` + `UploadReelBinary` + `GetVideoStatus` + `FinishReel`

#### 6b.6 Orchestration

`Operations::Facebook::PublishPost` chooses the path by media type and owns polling before the
finish/publish call. Driven by `Facebook::PublishPostJob` (Sidekiq, `default` queue); long video
processing can re-enqueue a `Facebook::PollVideoJob`.

---

## 7. Analytics / insights

> **Deprecations — verify before shipping:**
> - **Instagram:** `impressions`, `plays`, `video_views`, `clips_replays_count` deprecated
>   (Graph v22, effective **2025-04-21**). Replaced by **`views`**. Requesting them returns an
>   invalid-metric error. Account `website_clicks`/`phone_call_clicks` deprecated 2024-12-11.
> - **Facebook:** `page_impressions` being superseded by **`views`**-family. Legacy "page fans"
>   metrics retired (announced 2025-08-15; broader cleanup by **2026-06-15**).
> **→ Check the v25 insights reference for the current survivor list before coding metric names.**

### 7a. Instagram account insights

```
GET /v25.0/{IG_USER_ID}/insights
  metric=reach,views,profile_views,accounts_engaged,total_interactions,
         likes,comments,saves,shares,replies,profile_links_taps,website_clicks,
         follows_and_unfollows
  metric_type=total_value
  period=day
  since={unix}&until={unix}
  access_token={PAGE_TOKEN}
```

Follower count (field, not insight):
```
GET /v25.0/{IG_USER_ID}?fields=followers_count,follows_count,media_count&access_token={PAGE_TOKEN}
```

Demographics:
```
GET /v25.0/{IG_USER_ID}/insights
  metric=follower_demographics
  metric_type=total_value
  period=lifetime
  breakdown=city          # or country | age | gender
  timeframe=this_month
  access_token={PAGE_TOKEN}
```
→ `Vendors::Meta::Actions::GetAccountInsights` / `GetAccountFields`

### 7b. Instagram per-post insights

```
GET /v25.0/{MEDIA_ID}/insights
  metric=reach,views,likes,comments,saved,shares,total_interactions,
         profile_visits,follows,profile_activity
  access_token={PAGE_TOKEN}
```
The metric is `saved` (singular), NOT `saves`. Graph rejects the whole request on
one invalid metric name, so a typo here zeroes out every metric for the post.

Reels additionally: `ig_reels_avg_watch_time`, `ig_reels_video_view_total_time`.
Stories (24h window): `reach,views,replies,navigation,total_interactions`.
→ `Vendors::Meta::Actions::GetMediaInsights`

Persist daily snapshots via `Instagram::SyncInsightsJob` → `Operations::Instagram::SyncInsights`.

### 7c. Facebook page insights

```
GET /v25.0/{PAGE_ID}/insights
  metric=page_views_total,page_post_engagements,page_impressions_unique,
         page_fan_adds,page_video_views,page_actions_post_reactions_total
  period=day
  since={unix}&until={unix}
  access_token={PAGE_TOKEN}
```

Follower count (field):
```
GET /v25.0/{PAGE_ID}?fields=followers_count,fan_count,name&access_token={PAGE_TOKEN}
```
Note: `fan_count` is being retired — prefer `followers_count`.
→ `Vendors::Meta::Actions::GetPageInsights` / `GetPageFields`

### 7d. Facebook per-post insights

Engagement (likes/comments/shares) comes from the **post object**, NOT `/insights`.
Meta retired the `post_impressions*` and unique-reach families across all API
versions (2025-11 / 2026-06), and Graph fails the WHOLE `/insights` request on one
invalid metric — so relying on insights for engagement silently zeroes everything.

```
# Engagement — stable object fields (Vendors::Meta::Actions::GetPostEngagement)
GET /v25.0/{POST_ID}?fields=shares,comments.summary(true),reactions.summary(true)
  → reactions.summary.total_count = likes, comments.summary.total_count, shares.count
  access_token={PAGE_TOKEN}

# Reach/views — best-effort insights (Vendors::Meta::Actions::GetPostInsights)
GET /v25.0/{POST_ID}/insights
  metric=post_impressions_unique,post_impressions,post_video_views
  access_token={PAGE_TOKEN}
```
`GetPostInsights` (and `GetMediaInsights`) go through `Client#insights_get`, which
survives BOTH shapes Graph uses to reject a metric name — a deprecated metric must
never zero out the rest:

| Shape | Graph says | `insights_get` does |
|---|---|---|
| indexed | `metric[N] must be one of the following values: …` | drops metric N, retries |
| unindexed | `(#100) The value must be a valid insights metric` | probes each metric alone, keeps the survivors |

The probe logs `surviving insights metrics on {path}: [...]` at info — **read that
line off production to learn the currently-valid list** instead of guessing metric
names. Reach/views read 0 until at least one candidate in
`GetPostInsights::DEFAULT_METRICS` survives.

**The two halves are independent.** `Meta::Actions::SyncInsights#facebook_metrics`
attempts engagement and insights separately: whichever answers is kept, and only a
total failure raises. This is load-bearing — when the insights call was allowed to
unwind the method, it discarded the engagement numbers already fetched and every
Facebook post persisted as all zeros.

**Failure never becomes data.** `SyncInsights` returns `nil` when there is nothing
to read and raises when the read failed; `Operations::Posts::SyncMetrics` skips the
`PostMetric` write on either. An all-zero row is not "this post scored zero" — it is
a hole in the chart that outlives the outage that caused it.

**A finished token flags the account.** `Client` maps `DEAD_TOKEN_CODES`
(190/102/463/467 — invalid or expired token) to `Vendors::Base::AuthenticationError`
even though Graph answers HTTP 400, and `SyncMetrics` turns that into
`Operations::Social::FlagNeedsReauth` so the UI prompts a reconnect. Permission
gaps (`#10 pages_read_engagement`, `#200`) are deliberately excluded: they survive a
reconnect, so flagging them would nag the user to redo an OAuth hop that cannot fix
anything — those need the permission granted (App Review), not a new token.

Persist via `Facebook::SyncInsightsJob` → `Operations::Facebook::SyncInsights`.

---

## 8. Webhooks (shared endpoint)

Both IG and Facebook webhooks deliver to the **same endpoint** and are verified with the same app
secret. Ref: https://developers.facebook.com/docs/instagram-platform/webhooks/ and
https://developers.facebook.com/docs/graph-api/webhooks/

1. **App Dashboard → Webhooks**. Set **Callback URL** =
   `https://app.agencios.example/webhooks/meta` and **Verify Token** =
   `credentials.meta.webhook_verify_token`. Subscribe to both the **Instagram** and **Page** topics.
2. Meta sends `GET /webhooks/meta?hub.mode=subscribe&hub.challenge=...&hub.verify_token=...`.
   Your controller checks the verify token and **echoes `hub.challenge`** as plain text (200).
3. **IG fields to subscribe:** `comments`, `mentions`, `story_insights`.
4. **FB fields to subscribe:** `feed`, `mention`, `ratings`.
5. Connect each account to receive events:
```
# Instagram
POST /v25.0/{IG_USER_ID}/subscribed_apps
  subscribed_fields=comments,mentions
  access_token={PAGE_TOKEN}

# Facebook
POST /v25.0/{PAGE_ID}/subscribed_apps
  subscribed_fields=feed,mention
  access_token={PAGE_TOKEN}
```
→ `Vendors::Meta::Actions::SubscribeWebhooks` / `SubscribePageWebhooks`

6. For `POST` notifications, **verify `X-Hub-Signature-256`** =
   `sha256=HMAC_SHA256(app_secret, raw_body)` before processing. Enqueue to Sidekiq; respond 200
   fast.

> **mTLS note:** Meta is moving webhook certs to a Meta CA — by **2026-03-31** your endpoint must
> trust Meta's CA chain for mTLS-enabled webhooks. Ensure your TLS/cert config is current.

→ `Controllers::Webhooks::Meta` (verify + dispatch) → `Operations::Instagram::HandleWebhook` /
`Operations::Facebook::HandleWebhook`.

---

## 9. Rate limits & gotchas

- **IG publishing quota:** ~50 posts per rolling 24h (query `content_publishing_limit` — don't
  hardcode; check `quota_usage` + `config.quota_total`). Error code **9** = limit hit.
- **Container expiry 24h** — publish promptly after creating an IG container.
- **BUC rate limiting:** Graph calls are throttled per business/app. Read `X-Business-Use-Case-Usage`
  and `X-App-Usage` response headers; back off when near 100%.
- **FB scheduling window:** 10 min – 30 days (`scheduled_publish_time` + `published=false`).
- **Video is async on both networks:** poll `status_code=FINISHED` (IG) / `status=ready` (FB)
  before calling publish; too-early publish fails.
- **Public media URLs required** at IG publish time — fetch happens at Graph time; S3 URLs must
  be public/long-lived.
- **JPEG/PNG for images; H.264/AAC MP4 for video.** IG Reels: 9:16, ≤90s typical.
- **Page token vs user token:** all publish and insights calls use the **Page token**. The Page
  token only stays valid while the long-lived user token behind it is fresh — refresh on schedule.
- **`impressions`/`plays`/`video_views` are gone for IG** — use `views` (§7a).
- **Page fans metrics** are being retired for FB — use `followers_count`/`page_follows` (§7c).
- **FB Page role tasks:** connecting user needs `CREATE_CONTENT` (returned in `me/accounts` tasks).
- **<100 IG followers** ⇒ demographic insights unavailable; Stories need ≥5 viewers.

---

## 10. Testing checklist

**Setup:**
- [ ] App created (one app, both networks); App ID/secret in Rails credentials; redirect URI
      whitelisted.
- [ ] Add yourself as a **tester** and the IG account as a connected asset; Page role set.
- [ ] Everything below runs under **Standard Access** first.

**OAuth & tokens:**
- [ ] Dialog → code → short-lived → long-lived → `me/accounts` returns Page token + `tasks`
      (CREATE_CONTENT) + `instagram_business_account.id`. Both `SocialAccount` rows saved with
      encrypted tokens.
- [ ] `RefreshLongLivedToken` re-exchanges before `token_expires_at`.

**Instagram publishing:**
- [ ] Single image → container + publish → appears on IG.
- [ ] Carousel (2–3 children) publishes as one post.
- [ ] Reels (URL mode) → poll `status_code=FINISHED` → publish.
- [ ] Reels (resumable upload mode).
- [ ] `content_publishing_limit` blocks when quota is at cap.

**Facebook publishing:**
- [ ] Text/link post publishes; scheduled post (12 min out) appears scheduled.
- [ ] Single photo + multi-photo (attached_media) post.
- [ ] Video via 3-phase resumable → `status=ready` → visible on Page.
- [ ] Reel via `video_reels` start → rupload → poll → finish (PUBLISHED).

**Analytics:**
- [ ] IG account insights return `reach`/`views`/`follower_count`; requesting `impressions` errors.
- [ ] IG media insights return `views`/`likes`/`saves`/`shares`/`reach` for an image and a Reel.
- [ ] FB page insights return `page_views_total`/`page_post_engagements`; `impressions` errors.
- [ ] FB post insights return reactions/clicks/video views.

**Webhooks:**
- [ ] `GET` challenge echoed (200, plain text).
- [ ] Signed `POST` verified (`X-Hub-Signature-256`) + enqueued; mTLS CA updated.

**App Review:**
- [ ] Screencasts recorded for: `instagram_basic`, `instagram_content_publish`,
      `instagram_manage_insights`, `pages_show_list`, `pages_read_engagement`,
      `pages_manage_posts`, `read_insights`.
- [ ] Business Verification completed.
- [ ] App flipped to **Live**.

---

## API reference quick tables

Base `https://graph.facebook.com/v25.0` unless noted. All publish/insight calls use the **Page token**.

### Instagram actions

| `Vendors::Meta::Actions::*` | Method | Endpoint | SocialAccount fields | Scope |
|---|---|---|---|---|
| `ExchangeCodeForToken` | GET | `/oauth/access_token` (code) | — | — |
| `ExchangeLongLivedToken` | GET | `/oauth/access_token` (fb_exchange_token) | `user_access_token` | — |
| `ListPages` | GET | `/me/accounts?fields=...instagram_business_account` | `user_access_token` | `pages_show_list` |
| `GetLinkedInstagramAccount` | GET | `/{page_id}?fields=instagram_business_account` | `page_id`, `page_access_token` | `pages_read_engagement` |
| `CreateMediaContainer` | POST | `/{ig_user_id}/media` (image_url) | `ig_user_id`, `page_access_token` | `instagram_content_publish` |
| `CreateCarouselItem` | POST | `/{ig_user_id}/media` (is_carousel_item=true) | `ig_user_id`, `page_access_token` | `instagram_content_publish` |
| `CreateCarouselContainer` | POST | `/{ig_user_id}/media` (media_type=CAROUSEL) | `ig_user_id`, `page_access_token` | `instagram_content_publish` |
| `CreateReelsContainer` | POST | `/{ig_user_id}/media` (media_type=REELS) | `ig_user_id`, `page_access_token` | `instagram_content_publish` |
| `UploadResumableVideo` | POST | `rupload.facebook.com/ig-api-upload/v25.0/{creation_id}` | `page_access_token` | `instagram_content_publish` |
| `GetContainerStatus` | GET | `/{creation_id}?fields=status_code,status` | `page_access_token` | `instagram_basic` |
| `PublishMedia` | POST | `/{ig_user_id}/media_publish` (creation_id) | `ig_user_id`, `page_access_token` | `instagram_content_publish` |
| `GetPublishingLimit` | GET | `/{ig_user_id}/content_publishing_limit?fields=config,quota_usage` | `ig_user_id`, `page_access_token` | `instagram_content_publish` |
| `GetAccountInsights` | GET | `/{ig_user_id}/insights?metric=reach,views,...&metric_type=total_value` | `ig_user_id`, `page_access_token` | `instagram_manage_insights` |
| `GetAccountFields` | GET | `/{ig_user_id}?fields=followers_count,follows_count,media_count` | `ig_user_id`, `page_access_token` | `instagram_basic` |
| `GetMediaInsights` | GET | `/{media_id}/insights?metric=views,likes,...` | `page_access_token` | `instagram_manage_insights` |
| `SubscribeWebhooks` | POST | `/{ig_user_id}/subscribed_apps?subscribed_fields=comments,mentions` | `ig_user_id`, `page_access_token` | `instagram_basic` |

### Facebook actions

| `Vendors::Meta::Actions::*` | Method | Endpoint | SocialAccount fields | Scope |
|---|---|---|---|---|
| `CreateFeedPost` | POST | `/{page_id}/feed` (message, link, attached_media, scheduled_publish_time) | `page_id`, `page_access_token` | `pages_manage_posts` |
| `CreatePagePhoto` | POST | `/{page_id}/photos` (url/source, published) | `page_id`, `page_access_token` | `pages_manage_posts` |
| `StartVideoUpload` | POST | `/{page_id}/videos` (upload_phase=start, file_size) | `page_id`, `page_access_token` | `pages_manage_posts` |
| `TransferVideoChunk` | POST | `/{page_id}/videos` (upload_phase=transfer) | `page_id`, `page_access_token` | `pages_manage_posts` |
| `FinishVideoUpload` | POST | `/{page_id}/videos` (upload_phase=finish) | `page_id`, `page_access_token` | `pages_manage_posts` |
| `GetVideoStatus` | GET | `/{video_id}?fields=status` | `page_access_token` | `pages_read_engagement` |
| `StartReelUpload` | POST | `/{page_id}/video_reels` (upload_phase=start) | `page_id`, `page_access_token` | `pages_manage_posts` |
| `UploadReelBinary` | POST | `rupload.facebook.com/video-upload/v25.0/{video_id}` | `page_access_token` | `pages_manage_posts` |
| `FinishReel` | POST | `/{page_id}/video_reels` (upload_phase=finish, video_state=PUBLISHED) | `page_id`, `page_access_token` | `pages_manage_posts` |
| `GetPageInsights` | GET | `/{page_id}/insights?metric=page_views_total,...&period=day` | `page_id`, `page_access_token` | `read_insights` |
| `GetPageFields` | GET | `/{page_id}?fields=followers_count,fan_count,name` | `page_id`, `page_access_token` | `pages_read_engagement` |
| `GetPostInsights` | GET | `/{post_id}/insights?metric=post_impressions_unique,...` (reach/views) | `page_access_token` | `read_insights` |
| `GetPostEngagement` | GET | `/{post_id}?fields=shares,comments.summary(true),reactions.summary(true)` | `page_access_token` | `pages_read_engagement` |
| `SubscribePageWebhooks` | POST | `/{page_id}/subscribed_apps?subscribed_fields=feed,mention` | `page_id`, `page_access_token` | `pages_manage_posts` |
