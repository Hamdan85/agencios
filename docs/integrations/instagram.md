# Instagram Publishing + Analytics Integration Guide (agencios)

> Current as of June 2026. Graph API **v25.0** is the latest (released 2026-02-18); v23.0/v24.0 are still active. Pin a version in `Vendors::Meta::Client` (`META_GRAPH_VERSION = "v25.0"`).
>
> Doc sources cited inline. Primary refs:
> - https://developers.facebook.com/docs/instagram-platform/content-publishing/
> - https://developers.facebook.com/docs/instagram-platform/api-reference/instagram-user/insights/
> - https://developers.facebook.com/docs/instagram-platform/reference/instagram-media/insights/
> - https://developers.facebook.com/docs/instagram-platform/app-review/
> - https://developers.facebook.com/docs/graph-api/changelog

---

## 0. What you'll build (one paragraph)

A server-side integration in the Rails 8.1 app **agencios** that lets a workspace connect an **Instagram Professional account** (Business or Creator) linked to a Facebook Page, then **publishes** single images, carousels, and Reels via the Instagram Graph API (the 2-step *create container → publish container* pattern), and **reads analytics** (account-level reach/views/follower_count + per-media views/likes/comments/saves/shares/reach). All Graph calls are wrapped in `Vendors::Meta::Client` with one `Vendors::Meta::Actions::*` class per call; OAuth, token refresh, and publishing orchestration are `Operations::*` services driven by Sidekiq jobs; credentials live on the `SocialAccount` model (encrypted tokens) and Rails encrypted credentials.

---

## 1. Accounts & prerequisites

You need, before any code works:

1. **A Meta Business Portfolio (Business Manager)** at https://business.facebook.com — the app and Page must live under it for Advanced Access.
2. **A Facebook Page** owned by that business.
3. **An Instagram Professional account** (Business *or* Creator). Content Publishing historically required *Business*; as of 2025 Creator accounts can also publish via the Instagram Login flow, but **Business is the safe choice** — keep the account as Business. Ref: https://developers.facebook.com/docs/instagram-platform/content-publishing/
4. **The IG account linked to the Facebook Page** (IG app → Settings → Account → Sharing to other apps / linked Page; or Page → Linked accounts → Instagram).
5. **Business Verification** of your portfolio — **required** to get Advanced Access for `instagram_content_publish`. Ref: https://developers.facebook.com/docs/instagram-platform/app-review/
6. A **public HTTPS callback domain** for OAuth redirect + webhooks (ngrok is fine for dev).

> Two API "flows" exist. This guide uses the **Facebook Login flow** (host `graph.facebook.com`, scopes `instagram_basic`/`instagram_content_publish`, IG account reached through its parent Page) because it also gives you Facebook Page publishing in the same OAuth — see `facebook.md`. The newer **Instagram Login flow** (host `graph.instagram.com`, scopes `instagram_business_*`, no FB Page needed) is noted where it differs.

---

## 2. Create the Meta app (browser clickpath)

> Drive this clickpath in the Claude Chrome extension. Log in to the Facebook account that admins the Business Portfolio first.

1. Go to **https://developers.facebook.com/apps**.
2. Click **Create app** (top right).
3. **App details** screen: enter **App name** (`agencios`) and **App contact email** → **Next**.
4. **Use case** screen: select **"Other"** → **Next** (gives you a clean app you add products to). If prompted with a curated list, pick **"Manage everything on your Page"** or **"Access the Instagram API"** — but "Other" + manual product adds is the most predictable.
5. **App type**: choose **Business** → **Next** → **Create app** (re-enter password if asked).
6. You land on the **App Dashboard**. In the left rail click **App settings → Basic**. Copy **App ID** and **App secret** (click *Show*). You'll store these in Rails credentials (§5).
7. In the left rail / "Add products" panel, **Add** these products:
   - **Facebook Login for Business** (or classic *Facebook Login*) → click **Set up**.
   - **Instagram** → **Set up** (this is the "Instagram API setup with Facebook Login" / "Instagram Graph API" product).
   - **Webhooks** (optional, §8).
8. Under **Facebook Login → Settings**, add your OAuth **Valid OAuth Redirect URIs**, e.g. `https://app.agencios.example/oauth/meta/callback` and `https://<ngrok-id>.ngrok.app/oauth/meta/callback`. Save.
9. Under **App settings → Basic**, set **App Domains**, **Privacy Policy URL**, **Terms of Service URL**, **Category**, and a **Business verification** entry (App settings → Basic → "Verify"/Business use). These are blockers for App Review.
10. Switch the app from **Development** to **Live** only after App Review (top bar toggle).

---

## 3. Permissions & scopes

Request these in the OAuth `scope` param (Facebook Login flow):

| Scope | Why | Access level needed |
|---|---|---|
| `instagram_basic` | Read IG account id, media, basic fields | **Advanced** (App Review) |
| `instagram_content_publish` | Publish images/carousels/Reels | **Advanced** (App Review) + **Business Verification** |
| `instagram_manage_insights` | Read account + media insights | **Advanced** (App Review) |
| `pages_show_list` | List Pages the user manages (to find the linked IG account) | Advanced |
| `pages_read_engagement` | Read Page → IG link, Page-scoped data | Advanced |
| `business_management` | Resolve assets via the Business Portfolio (recommended for multi-asset) | Advanced |
| `public_profile` | Default, identifies the user | Standard |

Instagram Login flow equivalents (host `graph.instagram.com`): `instagram_business_basic`, `instagram_business_content_publish`, `instagram_business_manage_insights`, `instagram_business_manage_comments`.

**App Review / Advanced Access rules** (https://developers.facebook.com/docs/instagram-platform/app-review/):
- **Standard Access** = works only for users with a role on the app/business (devs, testers). Fine for building.
- **Advanced Access** = required to serve IG accounts you don't own. **`instagram_content_publish` is Advanced-Access-only and requires Business Verification.**
- Each permission is submitted separately with a **written use-case + screencast** of the exact user flow. Approval ~2–7 days. Build & test everything under Standard Access first.

---

## 4. OAuth flow (Facebook Login → long-lived token → IG account id)

All endpoints use base `https://graph.facebook.com/v25.0`. Ref: https://developers.facebook.com/docs/facebook-login/guides/access-tokens/get-long-lived/

**Step 1 — Send the user to the dialog** (browser redirect):
```
GET https://www.facebook.com/v25.0/dialog/oauth
  ?client_id={APP_ID}
  &redirect_uri=https://app.agencios.example/oauth/meta/callback
  &state={CSRF_TOKEN}
  &scope=instagram_basic,instagram_content_publish,instagram_manage_insights,pages_show_list,pages_read_engagement,business_management
  &response_type=code
```
→ `Operations::Meta::BuildAuthorizeUrl`

**Step 2 — Exchange `code` for a short-lived user token** (server, on callback):
```
GET /v25.0/oauth/access_token
  ?client_id={APP_ID}
  &client_secret={APP_SECRET}
  &redirect_uri={SAME_REDIRECT_URI}
  &code={CODE}
```
→ `Vendors::Meta::Actions::ExchangeCodeForToken`

**Step 3 — Exchange short-lived → long-lived user token (~60 days):**
```
GET /v25.0/oauth/access_token
  ?grant_type=fb_exchange_token
  &client_id={APP_ID}
  &client_secret={APP_SECRET}
  &fb_exchange_token={SHORT_LIVED_TOKEN}
```
Returns `access_token` + `expires_in`. → `Vendors::Meta::Actions::ExchangeLongLivedToken`

**Step 4 — List Pages + derive a Page token (Page tokens from a long-lived user token do not expire):**
```
GET /v25.0/me/accounts?access_token={LONG_LIVED_USER_TOKEN}
  &fields=id,name,access_token,instagram_business_account{id,username}
```
Each entry has the Page `id`, a non-expiring Page `access_token`, and (if linked) the `instagram_business_account.id` — **this is the IG account id you publish with.** → `Vendors::Meta::Actions::ListPages`

**Step 5 — (alternative) Resolve the IG id from a Page id directly:**
```
GET /v25.0/{PAGE_ID}?fields=instagram_business_account&access_token={PAGE_TOKEN}
```
→ `Vendors::Meta::Actions::GetLinkedInstagramAccount`

Orchestrate Steps 2–5 in `Operations::Meta::ConnectAccount`, persist to `SocialAccount`, then schedule `Meta::RefreshTokenJob` (Sidekiq) to re-exchange the long-lived user token before day 60.

> **Token refresh:** Facebook long-lived **user** tokens last ~60 days; refresh by repeating Step 3 with the current long-lived token before expiry. Page tokens derived from a *current* long-lived user token are effectively permanent. Store `token_expires_at` and refresh at ~day 50. → `Operations::Meta::RefreshLongLivedToken`.

---

## 5. Store credentials

**Rails encrypted credentials** (`EDITOR=nano bin/rails credentials:edit`):
```yaml
meta:
  app_id: "1234567890"
  app_secret: "xxxxxxxxxxxxxxxx"
  webhook_verify_token: "a-random-string-you-pick"   # §8
  graph_version: "v25.0"
```

**`SocialAccount` model** (`belongs_to :workspace`). Migration columns:
```ruby
create_table :social_accounts do |t|
  t.references :workspace, null: false, foreign_key: true
  t.string  :provider, null: false              # "instagram"
  t.string  :external_user_id                   # FB app-scoped user id (me.id)
  t.string  :page_id                            # linked FB Page id
  t.string  :ig_user_id                         # instagram_business_account.id  <-- publish target
  t.string  :username                           # IG @handle (display)
  t.text    :user_access_token                  # encrypted: long-lived USER token
  t.text    :page_access_token                  # encrypted: non-expiring PAGE token
  t.datetime :token_expires_at                  # user token expiry (~60d)
  t.jsonb   :scopes, default: []                # granted scopes (audit)
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

`Vendors::Meta::Client.new(social_account)` reads `page_access_token` (publishing/insights use the **Page token**) and `ig_user_id`.

---

## 6. Publishing flow

Base: `https://graph.facebook.com/v25.0`. Auth: **Page access token** (Facebook Login flow). Pattern is always **create container(s) → (poll status) → publish**. Media URLs must be **publicly reachable HTTPS** at publish time (host them on S3/ActiveStorage public URLs). Refs: https://developers.facebook.com/docs/instagram-platform/content-publishing/ and `.../reference/ig-user/media_publish/`.

### 6a. Single image
```
POST /v25.0/{IG_USER_ID}/media
  image_url=https://cdn.agencios.example/post.jpg
  caption=Your caption #hashtags
  alt_text=Accessible description           # optional, added 2025-03-24
  access_token={PAGE_TOKEN}
→ { "id": "<CREATION_ID>" }
```
Then publish:
```
POST /v25.0/{IG_USER_ID}/media_publish
  creation_id=<CREATION_ID>
  access_token={PAGE_TOKEN}
→ { "id": "<MEDIA_ID>" }
```
→ `Vendors::Meta::Actions::CreateMediaContainer` + `Vendors::Meta::Actions::PublishMedia`

### 6b. Carousel (2–10 items)
1. Create **each child** container with `is_carousel_item=true`:
```
POST /v25.0/{IG_USER_ID}/media
  image_url=...   (or video_url=... & media_type=VIDEO)
  is_carousel_item=true
  access_token={PAGE_TOKEN}
→ { "id": "<CHILD_ID_1>" } ... up to 10
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
3. **Publish** with `media_publish` + `creation_id` (same as 6a).
→ `Vendors::Meta::Actions::CreateCarouselItem` → `CreateCarouselContainer` → `PublishMedia`

### 6c. Reels / video (two upload modes)

**Mode A — hosted URL (simplest):**
```
POST /v25.0/{IG_USER_ID}/media
  media_type=REELS
  video_url=https://cdn.agencios.example/reel.mp4
  caption=...
  share_to_feed=true        # optional
  cover_url=...             # optional thumbnail
  access_token={PAGE_TOKEN}
→ { "id": "<CREATION_ID>" }
```

**Mode B — resumable upload (large/local files):** create container with `upload_type=resumable`, then PUT bytes to the upload host:
```
POST /v25.0/{IG_USER_ID}/media
  media_type=REELS
  upload_type=resumable
  caption=...
  access_token={PAGE_TOKEN}
→ { "id": "<CREATION_ID>", "uri": "<UPLOAD_URI>" }

POST https://rupload.facebook.com/ig-api-upload/v25.0/{CREATION_ID}
  Headers:
    Authorization: OAuth {PAGE_TOKEN}
    offset: 0
    file_size: {BYTES}
  Body: <raw video bytes>
```
Ref: https://developers.facebook.com/docs/instagram-platform/content-publishing/ (resumable upload). → `Vendors::Meta::Actions::CreateReelsContainer` + `Vendors::Meta::Actions::UploadResumableVideo`

**Then poll the container until `status_code=FINISHED` before publishing** (video processing is async):
```
GET /v25.0/{CREATION_ID}?fields=status_code,status&access_token={PAGE_TOKEN}
→ status_code ∈ { IN_PROGRESS | FINISHED | ERROR | EXPIRED | PUBLISHED }
```
→ `Vendors::Meta::Actions::GetContainerStatus`
Loop with backoff (5s → 30s) until `FINISHED`, then `media_publish` (6a).

### Container polling + the orchestrating operation
`Operations::Instagram::PublishPost` owns the whole dance:
1. Build container(s) via the right `Actions::Create*Container`.
2. For video/Reels, poll `GetContainerStatus` until `FINISHED` (or fail on `ERROR`/`EXPIRED`).
3. Call `PublishMedia`.
4. Save the returned `MEDIA_ID` to your `ScheduledPost`/`Post` record.

Run it from `Instagram::PublishPostJob` (Sidekiq, `default` queue). For Reels, either poll inside the job with `sleep`/re-enqueue, or split into `Instagram::PollContainerJob` that re-enqueues itself until `FINISHED`.

> **Container expiry: 24 hours.** Publish within 24h of creation or the container is unusable. Ref: https://developers.facebook.com/docs/instagram-platform/content-publishing/

---

## 7. Analytics / insights flow

> **Metric migration (verify before shipping):** `impressions` was **deprecated** for IG (Graph v22, retroactive from **2025-04-21**) and is replaced by **`views`**. `plays`, `video_views`, `clips_replays_count` are likewise folded into `views`. Account `website_clicks`/`phone_call_clicks`/etc. were deprecated 2024-12-11. Do **not** request `impressions`/`plays`/`video_views` — they return an invalid-metric error. Refs: https://developers.facebook.com/docs/instagram-platform/api-reference/instagram-user/insights/ and https://developers.facebook.com/docs/instagram-platform/reference/instagram-media/insights/

### 7a. Account / user insights
```
GET /v25.0/{IG_USER_ID}/insights
  metric=reach,views,profile_views,accounts_engaged,total_interactions,likes,comments,saves,shares,replies,profile_links_taps,website_clicks,follows_and_unfollows
  metric_type=total_value
  period=day
  since={unix}&until={unix}
  access_token={PAGE_TOKEN}
```
Time-series metric (no `metric_type`):
```
GET /v25.0/{IG_USER_ID}/insights?metric=follower_count&period=day&access_token={PAGE_TOKEN}
GET /v25.0/{IG_USER_ID}/insights?metric=online_followers&period=lifetime&access_token={PAGE_TOKEN}
```
Demographics (require `metric_type=total_value` + `breakdown` + `timeframe`):
```
GET /v25.0/{IG_USER_ID}/insights
  metric=follower_demographics
  metric_type=total_value
  period=lifetime
  breakdown=city            # or country | age | gender
  timeframe=this_month
```
Total followers right now is a **field**, not an insight:
```
GET /v25.0/{IG_USER_ID}?fields=followers_count,follows_count,media_count&access_token={PAGE_TOKEN}
```

Canonical account metric names (Facebook Login flow): `reach`, `views`, `follower_count`, `online_followers`, `accounts_engaged`, `total_interactions`, `likes`, `comments`, `saves`, `shares`, `replies`, `profile_links_taps`, `website_clicks`, `profile_views`, `follows_and_unfollows`, `profile_links_taps`, `follower_demographics`, `engaged_audience_demographics`, `reached_audience_demographics`. Most aggregate metrics now require `metric_type=total_value`. Account insights store ~90 days; needs **≥100 followers** for some demographics. → `Vendors::Meta::Actions::GetAccountInsights`

### 7b. Media / per-post insights
```
GET /v25.0/{MEDIA_ID}/insights
  metric=reach,views,likes,comments,saves,shares,total_interactions,profile_visits,follows,profile_activity
  access_token={PAGE_TOKEN}
```
Per media type (verify against the media-insights ref):
- **Image / Carousel:** `reach`, `views`, `likes`, `comments`, `saves`, `shares`, `total_interactions`, `profile_visits`, `profile_activity`, `follows`.
- **Reels:** `reach`, `views`, `likes`, `comments`, `saves`, `shares`, `total_interactions`, `ig_reels_avg_watch_time`, `ig_reels_video_view_total_time` (+ `clips_replays_count` deprecated → `views`).
- **Stories** (24h window): `reach`, `views`, `replies`, `navigation`, `total_interactions`, `profile_activity`, `follows`. Errors with `(#10) Not enough viewers` when <5 viewers.
- Some media use `metric_type=total_value`; albums have limited per-child insights.

→ `Vendors::Meta::Actions::GetMediaInsights`. Persist daily snapshots via `Instagram::SyncInsightsJob` (Sidekiq, scheduled) → `Operations::Instagram::SyncInsights`.

---

## 8. Webhooks (comments, mentions)

Optional but recommended for engagement features. Ref: https://developers.facebook.com/docs/instagram-platform/webhooks/

1. **App Dashboard → Webhooks → Instagram** (or in the Instagram product). Set **Callback URL** = `https://app.agencios.example/webhooks/meta` and **Verify Token** = `credentials.meta.webhook_verify_token`.
2. Meta sends `GET /webhooks/meta?hub.mode=subscribe&hub.challenge=...&hub.verify_token=...`. Your controller checks `hub.verify_token` matches and **echoes `hub.challenge`** as plain text (200).
3. **Subscribe to fields**: `comments`, `mentions`, `story_insights`, `live_comments`, `messages`.
4. Connect the account to receive events:
```
POST /v25.0/{IG_USER_ID}/subscribed_apps?subscribed_fields=comments,mentions&access_token={PAGE_TOKEN}
```
→ `Vendors::Meta::Actions::SubscribeWebhooks`
5. For `POST` notifications, **verify `X-Hub-Signature-256`** = `sha256=HMAC_SHA256(app_secret, raw_body)` before processing. Enqueue handling into Sidekiq; respond 200 fast.

→ `Controllers::Webhooks::Meta` (verify + dispatch) → `Operations::Instagram::HandleWebhook`.

---

## 9. Rate limits & gotchas

- **Publishing quota:** IG limits API posts per **rolling 24h** window (Meta's media_publish reference currently states **50**; older/other docs say 25 or 100 — **don't hardcode**, query it):
  ```
  GET /v25.0/{IG_USER_ID}/content_publishing_limit?fields=config,quota_usage&access_token={PAGE_TOKEN}
  ```
  `quota_usage` = posts used in the window; `config.quota_total` = the cap. Carousels count as **one** post. Refs: https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/content_publishing_limit/ → `Vendors::Meta::Actions::GetPublishingLimit`. Check this before every publish; error code **9** = limit hit.
- **Container expiry 24h** — publish promptly.
- **BUC (Business Use Case) rate limiting:** Graph calls are throttled per business/app; read the `X-Business-Use-Case-Usage` / `X-App-Usage` response headers and back off when near 100%. Capture them in `Vendors::Meta::Client` and surface to retry logic.
- **Public media URLs required** at publish time — IG fetches the bytes; ActiveStorage URLs must be public/long-lived.
- **JPEG/PNG for images; H.264/AAC MP4 for video.** Reels have aspect/duration constraints (9:16, ≤90s typical) — validate before upload to avoid `ERROR` containers.
- **Token classes:** publish/insights with the **Page token** (FB Login flow), not the user token. Page token only stays valid while the user token behind it is fresh — refresh on schedule.
- **`impressions`/`plays`/`video_views` are gone** — use `views` (§7).
- **<100 followers** ⇒ many demographic insights unavailable; Stories need ≥5 viewers.

---

## 10. Testing checklist

- [ ] App created, App ID/secret in Rails credentials; redirect URI whitelisted.
- [ ] Add yourself as a **tester** and the IG account as a connected asset; everything below works under **Standard Access** first.
- [ ] OAuth round-trip: dialog → code → short-lived → long-lived → `me/accounts` returns `instagram_business_account.id`; `SocialAccount` saved with encrypted tokens.
- [ ] `RefreshLongLivedToken` re-exchanges before `token_expires_at`.
- [ ] Publish single image → `media` then `media_publish` → appears on IG.
- [ ] Carousel (2–3 children) publishes as one post.
- [ ] Reels (URL mode) → poll `status_code` to `FINISHED` → publish; then try resumable upload mode.
- [ ] `content_publishing_limit` returns `quota_usage`/`config`; publish blocks when at cap.
- [ ] Account insights return `reach`/`views`/`follower_count`; requesting `impressions` errors (confirming deprecation).
- [ ] Media insights return `views`/`likes`/`saves`/`shares`/`reach` for an image and a Reel.
- [ ] Webhook verify (GET challenge) + signed POST handled.
- [ ] Submit **App Review** with screencasts for `instagram_basic`, `instagram_content_publish`, `instagram_manage_insights`; complete **Business Verification**; flip app to **Live**.

---

## API reference quick table

Base `https://graph.facebook.com/v25.0` unless noted. Scope column = the scope that gates it.

| `Vendors::Meta::Actions::*` | Method | Endpoint | Reads from `SocialAccount` | Scope |
|---|---|---|---|---|
| `ExchangeCodeForToken` | GET | `/oauth/access_token` (code) | — | — |
| `ExchangeLongLivedToken` | GET | `/oauth/access_token` (`grant_type=fb_exchange_token`) | `user_access_token` | — |
| `ListPages` | GET | `/me/accounts?fields=...instagram_business_account` | `user_access_token` | `pages_show_list` |
| `GetLinkedInstagramAccount` | GET | `/{page_id}?fields=instagram_business_account` | `page_id`,`page_access_token` | `pages_read_engagement` |
| `CreateMediaContainer` | POST | `/{ig_user_id}/media` (`image_url`) | `ig_user_id`,`page_access_token` | `instagram_content_publish` |
| `CreateCarouselItem` | POST | `/{ig_user_id}/media` (`is_carousel_item=true`) | `ig_user_id`,`page_access_token` | `instagram_content_publish` |
| `CreateCarouselContainer` | POST | `/{ig_user_id}/media` (`media_type=CAROUSEL`,`children`) | `ig_user_id`,`page_access_token` | `instagram_content_publish` |
| `CreateReelsContainer` | POST | `/{ig_user_id}/media` (`media_type=REELS`) | `ig_user_id`,`page_access_token` | `instagram_content_publish` |
| `UploadResumableVideo` | POST | `rupload.facebook.com/ig-api-upload/v25.0/{creation_id}` | `page_access_token` | `instagram_content_publish` |
| `GetContainerStatus` | GET | `/{creation_id}?fields=status_code,status` | `page_access_token` | `instagram_basic` |
| `PublishMedia` | POST | `/{ig_user_id}/media_publish` (`creation_id`) | `ig_user_id`,`page_access_token` | `instagram_content_publish` |
| `GetPublishingLimit` | GET | `/{ig_user_id}/content_publishing_limit?fields=config,quota_usage` | `ig_user_id`,`page_access_token` | `instagram_content_publish` |
| `GetAccountInsights` | GET | `/{ig_user_id}/insights?metric=reach,views,...&metric_type=total_value` | `ig_user_id`,`page_access_token` | `instagram_manage_insights` |
| `GetAccountFields` | GET | `/{ig_user_id}?fields=followers_count,follows_count,media_count` | `ig_user_id`,`page_access_token` | `instagram_basic` |
| `GetMediaInsights` | GET | `/{media_id}/insights?metric=views,likes,...` | `page_access_token` | `instagram_manage_insights` |
| `SubscribeWebhooks` | POST | `/{ig_user_id}/subscribed_apps?subscribed_fields=comments,mentions` | `ig_user_id`,`page_access_token` | `instagram_basic` |
