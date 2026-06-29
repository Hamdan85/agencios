# Facebook Page Publishing + Analytics Integration Guide (agencios)

> Current as of June 2026. Graph API **v25.0** is the latest (released 2026-02-18); v23.0/v24.0 still active. Pin a version in `Vendors::Meta::Client` (`META_GRAPH_VERSION = "v25.0"`).
>
> Doc sources cited inline. Primary refs:
> - https://developers.facebook.com/docs/pages-api/posts/
> - https://developers.facebook.com/docs/video-api/guides/publishing/
> - https://developers.facebook.com/docs/video-api/guides/reels-publishing
> - https://developers.facebook.com/docs/graph-api/reference/insights/
> - https://developers.facebook.com/blog/post/2025/08/15/page-insights-api-updates/
> - https://developers.facebook.com/docs/graph-api/changelog

---

## 0. What you'll build (one paragraph)

A server-side integration in the Rails 8.1 app **agencios** that connects a **Facebook Page** for a workspace, then **publishes** to that Page — text/link posts, single & multi-photo posts, videos (via the 3-phase Resumable Upload API), and Reels (via the chunked `video_reels` flow) — and **reads Page analytics** (page-level reach/views/engagement/follows + per-post reactions/comments/shares/video views). Every Graph call is wrapped in `Vendors::Meta::Client` with one `Vendors::Meta::Actions::*` class per call; OAuth, token refresh, and publishing orchestration are `Operations::*` services driven by Sidekiq jobs; credentials live on the `SocialAccount` model (encrypted **Page** access token) plus Rails encrypted credentials.

> This shares the same Meta app, OAuth, and `SocialAccount` model as `instagram.md` — connect both in one Facebook Login pass.

---

## 1. Accounts & prerequisites

1. **A Meta Business Portfolio (Business Manager)** — https://business.facebook.com.
2. **A Facebook Page** owned by that business; the connecting user must hold a Page role with the **CREATE_CONTENT** and **MANAGE** tasks.
3. **Business Verification** of the portfolio — required for Advanced Access to `pages_manage_posts`. Ref: https://developers.facebook.com/docs/permissions/
4. **A public HTTPS callback domain** for OAuth redirect + webhooks.
5. Page must have **≥100 likes** for most Page Insights to return data. Ref: https://developers.facebook.com/docs/graph-api/reference/insights/

> "New Pages experience": legacy concepts like *page fans* are being retired (see §7 deprecations). Publishing still uses a **Page access token**.

---

## 2. Create the Meta app (browser clickpath)

> If you already created the `agencios` app for Instagram (`instagram.md` §2), **reuse it** — just add **Facebook Login for Business** and confirm permissions. Otherwise:

1. Go to **https://developers.facebook.com/apps** → **Create app**.
2. **App details**: name `agencios`, contact email → **Next**.
3. **Use case**: choose **"Other"** → **Next** (or the curated **"Manage everything on your Page"**).
4. **App type**: **Business** → **Next** → **Create app**.
5. App Dashboard → **App settings → Basic**: copy **App ID** + **App secret**.
6. **Add products**:
   - **Facebook Login for Business** → **Set up**.
   - **Webhooks** (optional, §8).
7. **Facebook Login → Settings**: add **Valid OAuth Redirect URIs** (`https://app.agencios.example/oauth/meta/callback` + ngrok URL). Save.
8. **App settings → Basic**: set App Domains, Privacy Policy URL, Terms URL, Category; complete **Business verification**.
9. Flip **Development → Live** only after App Review.

---

## 3. Permissions & scopes

OAuth `scope` for Page publishing + insights:

| Scope | Why | Access level needed |
|---|---|---|
| `pages_show_list` | List the user's Pages | **Advanced** (App Review) |
| `pages_read_engagement` | Read Page content/metadata | **Advanced** (App Review) |
| `pages_manage_posts` | Create/edit/delete Page posts, photos, videos, Reels | **Advanced** (App Review) + Business Verification |
| `pages_read_user_content` | Read user-generated content on the Page (comments) | Advanced |
| `read_insights` | Read Page & post insights | **Advanced** (App Review) |
| `business_management` | Resolve Page assets via the Business Portfolio | Advanced |
| `public_profile` | Default | Standard |

**App Review rules** (https://developers.facebook.com/docs/permissions/):
- Everything beyond `public_profile`/`email` needs App Review for production (Advanced Access).
- **Each permission is submitted separately** with a written use-case + a **screencast of the full flow**. ~2–7 days.
- `pages_manage_posts` requires **Business Verification**.
- Under **Standard Access** the scopes work only for users with a role on the app/Page — build & test there first.

---

## 4. OAuth flow (Facebook Login → long-lived token → Page token)

Base `https://graph.facebook.com/v25.0`. Same as `instagram.md` §4 — one OAuth gives you Page + IG. Ref: https://developers.facebook.com/docs/facebook-login/guides/access-tokens/get-long-lived/

**Step 1 — Authorize dialog** (redirect):
```
GET https://www.facebook.com/v25.0/dialog/oauth
  ?client_id={APP_ID}
  &redirect_uri=https://app.agencios.example/oauth/meta/callback
  &state={CSRF_TOKEN}
  &scope=pages_show_list,pages_read_engagement,pages_manage_posts,read_insights,business_management
  &response_type=code
```
→ `Operations::Meta::BuildAuthorizeUrl`

**Step 2 — code → short-lived user token:**
```
GET /v25.0/oauth/access_token?client_id={APP_ID}&client_secret={APP_SECRET}&redirect_uri={REDIRECT}&code={CODE}
```
→ `Vendors::Meta::Actions::ExchangeCodeForToken`

**Step 3 — short-lived → long-lived user token (~60 days):**
```
GET /v25.0/oauth/access_token?grant_type=fb_exchange_token&client_id={APP_ID}&client_secret={APP_SECRET}&fb_exchange_token={SHORT_LIVED}
```
→ `Vendors::Meta::Actions::ExchangeLongLivedToken`

**Step 4 — list Pages + non-expiring Page tokens:**
```
GET /v25.0/me/accounts?fields=id,name,access_token,tasks&access_token={LONG_LIVED_USER_TOKEN}
```
Each entry has Page `id`, a **non-expiring** Page `access_token`, and `tasks` (must include `CREATE_CONTENT`). → `Vendors::Meta::Actions::ListPages`

Orchestrate in `Operations::Meta::ConnectAccount`; persist to `SocialAccount`. Page tokens derived from a *current* long-lived user token don't expire, but the user token does — schedule refresh.

> **Token refresh:** re-run Step 3 with the current long-lived user token before day 60 (`Operations::Meta::RefreshLongLivedToken`, fired by `Meta::RefreshTokenJob` at ~day 50). Store `token_expires_at`.

---

## 5. Store credentials

**Rails encrypted credentials** (shared with `instagram.md`):
```yaml
meta:
  app_id: "1234567890"
  app_secret: "xxxxxxxxxxxxxxxx"
  webhook_verify_token: "a-random-string-you-pick"
  graph_version: "v25.0"
```

**`SocialAccount`** (`belongs_to :workspace`) — same table as `instagram.md`; for Facebook, `provider="facebook"` and you publish with `page_access_token` + `page_id`:
```ruby
create_table :social_accounts do |t|
  t.references :workspace, null: false, foreign_key: true
  t.string  :provider, null: false              # "facebook"
  t.string  :external_user_id                   # FB app-scoped user id
  t.string  :page_id                            # publish target
  t.string  :page_name
  t.string  :ig_user_id                         # null for FB-only
  t.text    :user_access_token                  # encrypted long-lived USER token
  t.text    :page_access_token                  # encrypted non-expiring PAGE token  <-- used for FB publish/insights
  t.datetime :token_expires_at
  t.jsonb   :scopes, default: []
  t.timestamps
end
```
```ruby
class SocialAccount < ApplicationRecord
  belongs_to :workspace
  encrypts :user_access_token
  encrypts :page_access_token
end
```
`Vendors::Meta::Client.new(social_account)` reads `page_access_token` + `page_id`.

---

## 6. Publishing flow

Base `https://graph.facebook.com/v25.0`. Auth: **Page access token**. Refs: https://developers.facebook.com/docs/pages-api/posts/ , https://developers.facebook.com/docs/video-api/guides/publishing/ , https://developers.facebook.com/docs/video-api/guides/reels-publishing

### 6a. Text / link post
```
POST /v25.0/{PAGE_ID}/feed
  message=Hello world
  link=https://agencios.example          # optional; FB renders a link preview
  published=true
  access_token={PAGE_TOKEN}
→ { "id": "{PAGE_ID}_{POST_ID}" }
```
**Scheduled:** `published=false` + `scheduled_publish_time={unix}` (must be **10 min – 30 days** out).
→ `Vendors::Meta::Actions::CreateFeedPost`

### 6b. Single photo
```
POST /v25.0/{PAGE_ID}/photos
  url=https://cdn.agencios.example/photo.jpg     # or `source` = multipart file upload
  caption=Caption text
  published=true
  access_token={PAGE_TOKEN}
→ { "id": "<PHOTO_ID>", "post_id": "<POST_ID>" }
```
→ `Vendors::Meta::Actions::CreatePagePhoto`

### 6c. Multi-photo post (2-step: unpublished photos → feed with attached_media)
1. Upload each photo **unpublished** to get a media id:
```
POST /v25.0/{PAGE_ID}/photos
  url=https://cdn.agencios.example/p1.jpg
  published=false
  access_token={PAGE_TOKEN}
→ { "id": "<MEDIA_FBID_1>" }    # repeat per photo
```
2. Create the feed post attaching them:
```
POST /v25.0/{PAGE_ID}/feed
  message=Gallery caption
  attached_media[0]={"media_fbid":"<MEDIA_FBID_1>"}
  attached_media[1]={"media_fbid":"<MEDIA_FBID_2>"}
  access_token={PAGE_TOKEN}
→ { "id": "{PAGE_ID}_{POST_ID}" }
```
→ `Vendors::Meta::Actions::CreatePagePhoto` (published=false) + `Vendors::Meta::Actions::CreateFeedPost` (attached_media)

### 6d. Video — 3-phase Resumable Upload (create → publish pattern)
**Phase 1 — START** (declare file size, get a session):
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
  video_file_chunk=@<chunk bytes>           # multipart
  access_token={PAGE_TOKEN}
→ { "start_offset": "<next>", "end_offset": "<N>" }
```
**Phase 3 — FINISH** (commit + metadata):
```
POST /v25.0/{PAGE_ID}/videos
  upload_phase=finish
  upload_session_id=<SESSION>
  title=...
  description=...
  access_token={PAGE_TOKEN}
→ { "success": true }
```
Poll processing:
```
GET /v25.0/{VIDEO_ID}?fields=status&access_token={PAGE_TOKEN}
→ status.video_status ∈ { processing | ready | error }
```
→ `Vendors::Meta::Actions::StartVideoUpload` + `TransferVideoChunk` + `FinishVideoUpload` + `GetVideoStatus`

### 6e. Reels (chunked `video_reels` + rupload, finish-to-publish)
**Step 1 — START session:**
```
POST /v25.0/{PAGE_ID}/video_reels
  upload_phase=start
  access_token={PAGE_TOKEN}
→ { "video_id": "<VIDEO_ID>", "upload_url": "https://rupload.facebook.com/video-upload/v25.0/<VIDEO_ID>" }
```
**Step 2 — UPLOAD binary** to the rupload host:
```
POST https://rupload.facebook.com/video-upload/v25.0/{VIDEO_ID}
  Headers:
    Authorization: OAuth {PAGE_TOKEN}
    offset: 0
    file_size: {BYTES}
  Body: <raw video bytes>          # OR omit body and send header `file_url: https://cdn.../reel.mp4`
→ { "success": true }
```
**Step 3 — poll status:**
```
GET /v25.0/{VIDEO_ID}?fields=status&access_token={PAGE_TOKEN}
→ status phases: uploading_phase → processing_phase → publishing_phase
```
**Step 4 — FINISH / publish** (wait for processing to complete first):
```
POST /v25.0/{PAGE_ID}/video_reels
  video_id=<VIDEO_ID>
  upload_phase=finish
  video_state=PUBLISHED              # or DRAFT | SCHEDULED (+ scheduled_publish_time)
  description=Caption #hashtags
  access_token={PAGE_TOKEN}
→ { "success": true }
```
→ `Vendors::Meta::Actions::StartReelUpload` + `UploadReelBinary` + `GetVideoStatus` + `FinishReel`

### Orchestration
`Operations::Facebook::PublishPost` chooses the path by media type and owns polling for video/Reels (`status.video_status == "ready"` / Reels `publishing_phase` complete) before the finish/publish call. Driven by `Facebook::PublishPostJob` (Sidekiq, `default`); long video processing can re-enqueue a `Facebook::PollVideoJob`.

---

## 7. Analytics / insights flow

> **Deprecations (verify before shipping):** announced **2025-08-15**, the Page **`impressions`** metric is deprecated and replaced by **`views`**, and legacy **"page fans"** metrics are retired (90-day notice; enforcement from **2025-11-15**), with a broader Page Insights cleanup landing by **2026-06-15** (deprecated metrics return an invalid-metric error). Refs: https://developers.facebook.com/blog/post/2025/08/15/page-insights-api-updates/ and https://developers.facebook.com/docs/graph-api/reference/insights/ — **check the v25 insights reference for the exact survivor list before coding metric names.**

### 7a. Page-level insights
```
GET /v25.0/{PAGE_ID}/insights
  metric=page_views_total,page_post_engagements,page_impressions_unique,page_fan_adds,page_video_views,page_actions_post_reactions_total
  period=day                         # day | week | days_28
  since={unix}&until={unix}
  access_token={PAGE_TOKEN}
```
Common still-supported Page metrics (confirm each against v25 ref, since the Nov-2025/Jun-2026 cleanup is in flight):
- `page_views_total` — Page views.
- `page_post_engagements` — total engagement on Page posts.
- `page_impressions`, `page_impressions_unique` (the unique flavor = "reach"; note plain `page_impressions` is being superseded by **`views`**-family metrics).
- `page_fans` (legacy "fans"; being retired) / `page_fan_adds`, `page_fan_removes` — new follows surfaced via **`page_follows` / `page_daily_follows`** in the new experience.
- `page_video_views`, `page_video_views_paid`, `page_video_complete_views_30s`.
- `page_actions_post_reactions_total` — reactions breakdown (like/love/wow/…).
→ `Vendors::Meta::Actions::GetPageInsights`

Current follower count is a **field**, not an insight (note `fan_count` itself is affected by the fans deprecation; prefer `followers_count`):
```
GET /v25.0/{PAGE_ID}?fields=followers_count,fan_count,name&access_token={PAGE_TOKEN}
```
→ `Vendors::Meta::Actions::GetPageFields`

### 7b. Per-post insights
```
GET /v25.0/{POST_ID}/insights
  metric=post_impressions,post_impressions_unique,post_engaged_users,post_clicks,post_reactions_by_type_total,post_video_views
  access_token={PAGE_TOKEN}
```
Useful post metrics: `post_impressions`, `post_impressions_unique`, `post_engaged_users`, `post_clicks`, `post_reactions_by_type_total`, `post_video_views`, `post_video_avg_time_watched`, `post_video_complete_views_30s`. (Same `views` migration applies — `post_impressions` is being superseded; check v25 ref.)
→ `Vendors::Meta::Actions::GetPostInsights`. Persist via `Facebook::SyncInsightsJob` (Sidekiq, scheduled) → `Operations::Facebook::SyncInsights`.

---

## 8. Webhooks (comments, mentions, feed)

Ref: https://developers.facebook.com/docs/graph-api/webhooks/

1. **App Dashboard → Webhooks → Page**. Callback URL `https://app.agencios.example/webhooks/meta`, Verify Token = `credentials.meta.webhook_verify_token`.
2. Verification: Meta `GET`s with `hub.mode=subscribe&hub.challenge=...&hub.verify_token=...`; verify the token and **echo `hub.challenge`** (200, plain text).
3. Subscribe to **Page fields**: `feed` (posts/comments/reactions), `mention`, `ratings`, `messages` (if Messenger).
4. Connect the Page to the app's webhook:
```
POST /v25.0/{PAGE_ID}/subscribed_apps?subscribed_fields=feed,mention&access_token={PAGE_TOKEN}
```
→ `Vendors::Meta::Actions::SubscribePageWebhooks`
5. Verify `X-Hub-Signature-256` (`sha256=HMAC_SHA256(app_secret, raw_body)`) on POSTs; enqueue to Sidekiq; respond 200 fast.
→ `Controllers::Webhooks::Meta` → `Operations::Facebook::HandleWebhook`.

> **Webhook mTLS note:** Meta is moving webhook certs to a Meta CA — **by 2026-03-31** your webhook endpoint must trust Meta's CA chain for mTLS-enabled webhooks. Ensure your TLS/cert config is current. Ref: https://developers.facebook.com/docs/graph-api/changelog

---

## 9. Rate limits & gotchas

- **BUC (Business Use Case) / platform rate limiting:** Page calls are throttled per app + per Page. Read `X-App-Usage` and `X-Business-Use-Case-Usage` response headers; back off at ~90%. Capture in `Vendors::Meta::Client`.
- **Scheduling window:** scheduled posts must be **10 minutes – 30 days** out (`scheduled_publish_time` + `published=false`).
- **Video/Reels are async:** poll `status` to `ready` / publishing complete before the finish step or reading insights; a too-early publish fails.
- **`source` (file upload) vs `url`:** photos accept a multipart `source` OR a public `url`. Big videos must use the resumable/`video_reels` chunked flow, not a single POST.
- **Page role tasks:** the connecting user needs `CREATE_CONTENT` on the Page (`tasks` in `me/accounts`); otherwise publish 403s.
- **`impressions`/`page fans` are going away** — migrate to `views`/`page_follows`-family metrics (§7).
- **≥100 likes** for most Page Insights; data refreshes ~every 24h.
- **Token classes:** publish/insights use the **Page token**, valid only while the long-lived user token behind it is fresh — refresh on schedule.

---

## 10. Testing checklist

- [ ] App + Facebook Login product configured; redirect URI whitelisted; App ID/secret in credentials.
- [ ] Add yourself/testers with a Page role; verify under **Standard Access** first.
- [ ] OAuth: dialog → code → long-lived user token → `me/accounts` returns Page id + Page token with `CREATE_CONTENT` task; `SocialAccount` saved with encrypted tokens.
- [ ] `RefreshLongLivedToken` re-exchanges before `token_expires_at`.
- [ ] Text/link post publishes; scheduled post (12 min out) appears scheduled.
- [ ] Single photo + multi-photo (attached_media) post.
- [ ] Video via 3-phase resumable upload → `status=ready` → visible on Page.
- [ ] Reel via `video_reels` start → rupload binary → poll → finish (`video_state=PUBLISHED`).
- [ ] Page insights return `page_views_total`/`page_post_engagements`/`views`; requesting `impressions` errors (confirming deprecation).
- [ ] Post insights return reactions/clicks/video views.
- [ ] Webhook verify (GET challenge) + signed POST handled; mTLS CA updated.
- [ ] Submit **App Review** with screencasts for `pages_show_list`, `pages_read_engagement`, `pages_manage_posts`, `read_insights`; complete **Business Verification**; flip to **Live**.

---

## API reference quick table

Base `https://graph.facebook.com/v25.0` unless noted. All publish/insight calls use the **Page** token.

| `Vendors::Meta::Actions::*` | Method | Endpoint | Reads from `SocialAccount` | Scope |
|---|---|---|---|---|
| `ExchangeCodeForToken` | GET | `/oauth/access_token` (code) | — | — |
| `ExchangeLongLivedToken` | GET | `/oauth/access_token` (`grant_type=fb_exchange_token`) | `user_access_token` | — |
| `ListPages` | GET | `/me/accounts?fields=id,name,access_token,tasks` | `user_access_token` | `pages_show_list` |
| `CreateFeedPost` | POST | `/{page_id}/feed` (`message`,`link`,`attached_media`,`scheduled_publish_time`) | `page_id`,`page_access_token` | `pages_manage_posts` |
| `CreatePagePhoto` | POST | `/{page_id}/photos` (`url`/`source`,`published`) | `page_id`,`page_access_token` | `pages_manage_posts` |
| `StartVideoUpload` | POST | `/{page_id}/videos` (`upload_phase=start`,`file_size`) | `page_id`,`page_access_token` | `pages_manage_posts` |
| `TransferVideoChunk` | POST | `/{page_id}/videos` (`upload_phase=transfer`,`start_offset`,`video_file_chunk`) | `page_id`,`page_access_token` | `pages_manage_posts` |
| `FinishVideoUpload` | POST | `/{page_id}/videos` (`upload_phase=finish`,`title`,`description`) | `page_id`,`page_access_token` | `pages_manage_posts` |
| `GetVideoStatus` | GET | `/{video_id}?fields=status` | `page_access_token` | `pages_read_engagement` |
| `StartReelUpload` | POST | `/{page_id}/video_reels` (`upload_phase=start`) | `page_id`,`page_access_token` | `pages_manage_posts` |
| `UploadReelBinary` | POST | `rupload.facebook.com/video-upload/v25.0/{video_id}` (`offset`,`file_size`/`file_url`) | `page_access_token` | `pages_manage_posts` |
| `FinishReel` | POST | `/{page_id}/video_reels` (`upload_phase=finish`,`video_state=PUBLISHED`,`description`) | `page_id`,`page_access_token` | `pages_manage_posts` |
| `GetPageInsights` | GET | `/{page_id}/insights?metric=page_views_total,page_post_engagements,...&period=day` | `page_id`,`page_access_token` | `read_insights` |
| `GetPageFields` | GET | `/{page_id}?fields=followers_count,fan_count,name` | `page_id`,`page_access_token` | `pages_read_engagement` |
| `GetPostInsights` | GET | `/{post_id}/insights?metric=post_engaged_users,post_clicks,...` | `page_access_token` | `read_insights` |
| `SubscribePageWebhooks` | POST | `/{page_id}/subscribed_apps?subscribed_fields=feed,mention` | `page_id`,`page_access_token` | `pages_manage_posts` |
