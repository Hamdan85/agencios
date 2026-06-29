# TikTok for Developers — Publishing & Analytics Integration Guide

> **Scope & audience.** This document does two jobs:
> 1. It is a **clickpath runbook** for a browser-operating Claude agent (the *Claude Chrome extension*) to set up a TikTok developer app end-to-end on `developers.tiktok.com`.
> 2. It is the **backend implementation plan** for the Rails 8.1 app **`agencios`** (vendor wrappers under `app/services/vendors/TikTok/`, domain side effects in `app/services/operations/`, OAuth tokens on a `SocialAccount` model, Sidekiq for background work, credentials in Rails encrypted credentials).
>
> **Currency note.** Verified against the official docs as of **2026-06**. TikTok migrated the *Share Video API* into the **Content Posting API** and renamed legacy webhook events (`video.publish.complete → post.publish.complete`). Two API generations coexist in the docs — this guide uses the **v2** endpoints (`open.tiktokapis.com/v2/...`) exclusively. Always re-check the [Changelog](https://developers.tiktok.com/doc/changelog) before a release.

---

## 0. What you'll build

A workspace-scoped TikTok integration for `agencios` that can:

- **Connect** a TikTok creator account to a `workspace` via OAuth 2.0 (Login Kit), storing rotating access/refresh tokens on a `SocialAccount` record.
- **Publish** to that account via the **Content Posting API**:
  - **Direct Post** of a video — `init` → upload (`FILE_UPLOAD` chunks **or** `PULL_FROM_URL`) → poll status.
  - **Photo / carousel** post (up to 35 images) via the unified `content/init` endpoint.
  - Always preceded by the **mandatory `creator_info/query`** call (a hard TikTok review requirement).
- **Read analytics** via the **Display API**: account stats (`/v2/user/info/`) and per-video engagement metrics (`/v2/video/list/`, `/v2/video/query/`) — likes, comments, shares, views.
- **React to webhooks** for post lifecycle and de-authorization events.

**Critical constraint up front:** until your app is **audited/approved**, every post is forced to `SELF_ONLY` (private) and only up to **5 users** may post per 24h. Build and test against this, then submit for audit to go public. See [§3](#3-scopes--which-need-audit) and [§9](#9-rate-limits--gotchas).

| Capability | TikTok product | Key endpoint(s) | Rails call site |
|---|---|---|---|
| Connect account | Login Kit (OAuth) | `auth/authorize/`, `oauth/token/` | `Vendors::TikTok::Actions::ExchangeCode`, `Vendors::TikTok::Actions::RefreshToken` |
| Pre-post info | Content Posting API | `post/publish/creator_info/query/` | `Vendors::TikTok::Actions::QueryCreatorInfo` |
| Publish video | Content Posting API | `post/publish/video/init/` + upload + `status/fetch/` | `Vendors::TikTok::Actions::PublishVideo` |
| Publish photos | Content Posting API | `post/publish/content/init/` | `Vendors::TikTok::Actions::PublishPhoto` |
| Account stats | Display API | `user/info/` | `Vendors::TikTok::Actions::FetchUserInfo` |
| Video metrics | Display API | `video/list/`, `video/query/` | `Vendors::TikTok::Actions::ListVideos` |

---

## 1. Accounts & prerequisites

1. **A TikTok account** that will own the developer org. Use the business/agency account, not a personal throwaway — it must be in good standing.
2. **A TikTok Developer account.** Register at <https://developers.tiktok.com/signup> with email (you can also sign in with your TikTok account). ([Create an app](https://developers.tiktok.com/doc/getting-started-create-an-app))
3. **An Organization** representing the owning company (recommended, not strictly required). Apps belong to an org; this matters for audits and team access.
4. **The TikTok creator accounts** you'll publish to. During sandbox/unaudited phase you can add up to **10 target users** to a sandbox and only **5 distinct users may post per 24h**.
5. **A verifiable domain** you control (HTTPS, no redirects) if you intend to use `PULL_FROM_URL` for media. You'll verify ownership in the portal (see [§9](#9-rate-limits--gotchas)).
6. **HTTPS callback URLs**: an OAuth redirect URI and (optionally) a webhook endpoint. Both must be HTTPS and registered in the portal.

---

## 2. Create the app — exact browser clickpath

> **For the Claude Chrome agent.** Execute these steps literally in `developers.tiktok.com`. Button/section labels are quoted exactly. If a label has drifted, match on the closest visible text and continue. Cross-references: [Create an app](https://developers.tiktok.com/doc/getting-started-create-an-app), [Sandbox blog](https://developers.tiktok.com/blog/introducing-sandbox).

### 2.1 Register the app
1. Go to <https://developers.tiktok.com/> and **log in**.
2. Click the **profile icon** (top-right nav) → click **"Manage apps"**.
3. Click **"Connect an app"**.
4. In the owner dropdown, **select your Organization**, then click **"Confirm"**. The app shell is created and you land on the app page.

### 2.2 Fill App details (left-nav → "App details")
5. Under **"Basic information"**: upload an app **icon** (1024×1024 px, ≤5 MB), enter **app name**, select **category**, write a **description**.
6. Under **"Platforms"**: select **Web** (and/or Desktop/Android/iOS). For **Web**, provide the website URL. For Android provide package name + App Link/Deep Link; for iOS the bundle ID + Universal Link.
7. Locate **"Credentials"** in App details — this shows **"Client key"** and **"Client secret"**. **Copy both** (the agent should report these back; they go into Rails credentials, never the repo — see [§5](#5-store-credentials)).

### 2.3 Use Sandbox first (recommended)
8. On the **"Manage apps"** page (or app header), toggle the switch next to the app name to **Sandbox mode**, click **"Create Sandbox"**, name it, and optionally **clone** existing config. (Up to **5 sandboxes** per app; share with up to **10 target users**.) Sandbox lets you test Login Kit + Content Posting API **without submitting for review**.

### 2.4 Add products (left-nav → "Products" → "Add products")
9. Click **"Add products"**. Add:
   - **Login Kit** — required for OAuth. In its config set the **Redirect URI** (e.g. `https://app.agencios.com/auth/tiktok/callback`). Add web + native variants as needed.
   - **Content Posting API** — enables publishing. Choose the posting capabilities you need; configure **Direct Post** (publishes immediately) and/or **Upload** (sends a draft to the creator's TikTok inbox).
   - **Display API** *(optional but recommended for analytics)* — enables `user/info`, `video/list`, `video/query`.
10. *(Optional)* Add **Webhooks** product and set the **webhook callback URL** (HTTPS) — see [§8](#8-webhooks).

### 2.5 Scopes (left-nav → "Scopes")
11. In **"Scopes"**, enable the scopes you need (see [§3](#3-scopes--which-need-audit)). `user.info.basic` is added by default with Login Kit. Some scopes are gated and only become active after audit.

### 2.6 Verify URL properties
12. Click **"URL properties"** (app page top). Add your **Domain** or **URL Prefix** property. Download the verification file (`tiktok_verify_xxxxx.html`), host it at the domain root, then click **"Verify"**. Required for **Link Sharing** and for **`PULL_FROM_URL`** media domains. ([Media transfer guide](https://developers.tiktok.com/doc/content-posting-api-media-transfer-guide))

### 2.7 Submit for review (only when going to production)
13. Move sandbox config to a **production Draft** ("import your Sandbox configuration to a Draft").
14. Open the **"App review"** section. Explain **each product and scope** and how it's used. Upload **1–5 demo videos** (≤50 MB each) showing the **complete end-to-end flow** (including the creator-info screen, privacy selector, and disclosure toggles — see [§9](#9-rate-limits--gotchas)).
15. Click **"Submit for review"**. Audit typically takes **~2–4 weeks** with possible feedback rounds.

---

## 3. Scopes — which need audit

Set scopes in the **Scopes** section and request them in the OAuth `scope` param (comma-separated). ([Scopes overview](https://developers.tiktok.com/doc/scopes-overview))

| Scope | Product | Grants | Audit / notes |
|---|---|---|---|
| `user.info.basic` | Login Kit / Display | `open_id`, `union_id`, `avatar_url`, `avatar_url_100`, `avatar_large_url`, `display_name` | Added by default with Login Kit. Generally available. |
| `user.info.profile` | Display | `bio_description`, `profile_deep_link`, `is_verified`, `username` | Requires enabling/approval. |
| `user.info.stats` | Display | `follower_count`, `following_count`, `likes_count`, `video_count` | Requires enabling/approval — **this is the account-analytics scope**. |
| `video.list` | Display | Read the user's **public** videos + per-video metrics (`like_count`, `comment_count`, `share_count`, `view_count`) | Requires Display API approval. **The video-analytics scope.** |
| `video.publish` | Content Posting | **Direct Post** (publish immediately) of video & photo | Works in sandbox/unaudited but posts are **`SELF_ONLY`** until the app is audited. |
| `video.upload` | Content Posting | **Upload** content as a **draft to the creator's inbox** (creator finishes in TikTok) | Same unaudited restriction applies. |

> **Rule of thumb.** Posting publicly, reading profile, reading stats, and listing videos all depend on **app audit/approval**. `video.publish`/`video.upload` *function* before audit but are clamped to `SELF_ONLY`. Always request the **minimum** scopes the audit can justify.

**Recommended scope set for `agencios`:**
`user.info.basic,user.info.profile,user.info.stats,video.publish,video.upload,video.list`

---

## 4. OAuth flow

Login Kit, OAuth 2.0 Authorization Code (with optional PKCE for native apps). ([Token management](https://developers.tiktok.com/doc/oauth-user-access-token-management))

### 4.1 Authorization request (redirect the user's browser)

```
GET https://www.tiktok.com/v2/auth/authorize/
  ?client_key={CLIENT_KEY}
  &scope=user.info.basic,user.info.profile,user.info.stats,video.publish,video.upload,video.list
  &response_type=code
  &redirect_uri={URL-ENCODED REGISTERED REDIRECT URI}
  &state={CSRF_TOKEN}
  # &code_challenge={...}&code_challenge_method=S256   # PKCE (native only)
```
- `redirect_uri` must **exactly** match a redirect URI registered in Login Kit.
- `state` is your CSRF nonce — persist it and validate on callback.
- On approval TikTok redirects to `redirect_uri?code={AUTH_CODE}&state={...}&scopes=...`. **URL-decode `code`** before using it.

### 4.2 Token exchange — `grant_type=authorization_code`

```
POST https://open.tiktokapis.com/v2/oauth/token/
Content-Type: application/x-www-form-urlencoded

client_key={CLIENT_KEY}
client_secret={CLIENT_SECRET}
code={URL-DECODED AUTH CODE}
grant_type=authorization_code
redirect_uri={SAME REGISTERED REDIRECT URI}
# code_verifier={...}   # PKCE only
```

**Response (JSON):**
```json
{
  "access_token": "act.xxx",
  "expires_in": 86400,
  "refresh_token": "rft.xxx",
  "refresh_expires_in": 31536000,
  "open_id": "_open_id_string_",
  "scope": "user.info.basic,video.publish,...",
  "token_type": "Bearer"
}
```
- `access_token` lifetime ≈ **24h** (`expires_in` = 86400).
- `refresh_token` lifetime ≈ **365 days** (`refresh_expires_in` = 31536000).
- `open_id` uniquely identifies the user **for this app**; `union_id` (via user info) is stable across your apps.

### 4.3 Refresh — `grant_type=refresh_token` (with rotation)

```
POST https://open.tiktokapis.com/v2/oauth/token/
Content-Type: application/x-www-form-urlencoded

client_key={CLIENT_KEY}
client_secret={CLIENT_SECRET}
grant_type=refresh_token
refresh_token={CURRENT_REFRESH_TOKEN}
```

> **Rotation (critical).** Per TikTok: *"The returned `refresh_token` may be different than the one passed in the payload. You must use the newly-returned token if the value is different than the previous one."* Always **overwrite both** `access_token` and `refresh_token` with the response, and reset both expiry timestamps. Refreshing also **resets the 365-day refresh window** — refresh proactively before `access_token` expiry to avoid full re-auth. This rotation is handled in an **operation** (`Operations::TikTok::RefreshAccessToken`), not in the vendor client.

### 4.4 Revoke (disconnect)

```
POST https://open.tiktokapis.com/v2/oauth/revoke/
Content-Type: application/x-www-form-urlencoded

client_key={CLIENT_KEY}
client_secret={CLIENT_SECRET}
token={ACCESS_TOKEN}
```

---

## 5. Store credentials

### 5.1 Rails encrypted credentials (`EDITOR=nano bin/rails credentials:edit`)

```yaml
tiktok:
  client_key: "awxxxxxxxxxxxxx"
  client_secret: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  # used to verify the TikTok-Signature webhook header (= client_secret unless TikTok issues a separate one)
```
- **Never** put `client_key`/`client_secret` in `.env` or the repo. `.env` is for non-sensitive infra only.
- `redirect_uri` and webhook URL can be derived from `SystemConfig.app_host` at runtime.

### 5.2 `SocialAccount` model & columns

`SocialAccount belongs_to :workspace`. One row per connected TikTok creator account. Encrypt the token columns with Active Record Encryption.

Migration:
```ruby
class CreateSocialAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :social_accounts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :provider,            null: false, default: "tiktok"   # multi-network ready
      t.string  :provider_open_id,    null: false                       # TikTok open_id
      t.string  :provider_union_id                                      # stable across your apps
      t.string  :username
      t.string  :display_name
      t.string  :avatar_url

      t.text    :access_token                                            # encrypted
      t.text    :refresh_token                                           # encrypted
      t.datetime :access_token_expires_at
      t.datetime :refresh_token_expires_at
      t.string  :scopes                                                  # comma-separated granted scopes

      t.datetime :revoked_at
      t.timestamps
    end
    add_index :social_accounts, [:provider, :provider_open_id], unique: true
    add_index :social_accounts, [:workspace_id, :provider]
  end
end
```

```ruby
class SocialAccount < ApplicationRecord
  belongs_to :workspace

  encrypts :access_token
  encrypts :refresh_token

  scope :tiktok, -> { where(provider: "tiktok") }

  def access_token_expired?(skew: 5.minutes)
    access_token_expires_at.nil? || access_token_expires_at <= Time.current + skew
  end

  def refresh_expired?
    refresh_token_expires_at.present? && refresh_token_expires_at <= Time.current
  end

  def connected? = revoked_at.nil? && refresh_token.present?
end
```

| OAuth/API field | `SocialAccount` column |
|---|---|
| `open_id` | `provider_open_id` |
| `union_id` (from user info) | `provider_union_id` |
| `access_token` | `access_token` (encrypted) |
| `refresh_token` | `refresh_token` (encrypted) |
| `expires_in` → now + N s | `access_token_expires_at` |
| `refresh_expires_in` → now + N s | `refresh_token_expires_at` |
| `scope` | `scopes` |
| `display_name` / `username` / `avatar_url` (user info) | `display_name` / `username` / `avatar_url` |

---

## 6. Publishing flow — Content Posting API

Base URL: `https://open.tiktokapis.com`. All calls send `Authorization: Bearer {access_token}`. **Every post must be preceded by `creator_info/query`** (TikTok verifies this in review). ([Get started](https://developers.tiktok.com/doc/content-posting-api-get-started), [Direct Post ref](https://developers.tiktok.com/doc/content-posting-api-reference-direct-post), [Content sharing guidelines](https://developers.tiktok.com/doc/content-sharing-guidelines))

### 6.0 Mandatory: Query creator info (must precede every post)

```
POST /v2/post/publish/creator_info/query/
Authorization: Bearer {access_token}
Content-Type: application/json; charset=UTF-8
{}
```
Response `data` includes:
- `creator_avatar_url`, `creator_username`, `creator_nickname` — **you must display nickname + avatar in your UI** before posting (hard review requirement).
- `privacy_level_options` — array; **only offer these to the user**. For unaudited apps this will effectively be `["SELF_ONLY"]`.
- `comment_disabled`, `duet_disabled`, `stitch_disabled` — current creator capabilities; grey out unavailable interaction toggles.
- `max_video_post_duration_sec` — reject videos longer than this.

> Stop and surface an error if the creator cannot currently post (e.g. duration over limit, or no privacy option allowed).

### 6.1 Direct Post a video — init

```
POST /v2/post/publish/video/init/
Authorization: Bearer {access_token}
Content-Type: application/json; charset=UTF-8
```
**FILE_UPLOAD body:**
```json
{
  "post_info": {
    "title": "Caption with #hashtags @mentions",
    "privacy_level": "SELF_ONLY",
    "disable_duet": false,
    "disable_comment": false,
    "disable_stitch": false,
    "video_cover_timestamp_ms": 1000,
    "brand_content_toggle": false,
    "brand_organic_toggle": false,
    "is_aigc": false
  },
  "source_info": {
    "source": "FILE_UPLOAD",
    "video_size": 30567100,
    "chunk_size": 10000000,
    "total_chunk_count": 3
  }
}
```
**PULL_FROM_URL body** (`source_info` only differs):
```json
{
  "source": "PULL_FROM_URL",
  "video_url": "https://verified-domain.agencios.com/media/clip.mp4"
}
```
`post_info` field reference:
- `privacy_level` — one of `PUBLIC_TO_EVERYONE`, `MUTUAL_FOLLOW_FRIENDS`, `FOLLOWER_OF_CREATOR`, `SELF_ONLY` (**required**). Must be one of `privacy_level_options` from creator_info. **Unaudited → `SELF_ONLY` only.**
- `title` — up to 2200 UTF-16 runes (caption; hashtags/mentions live here).
- `disable_duet` / `disable_stitch` / `disable_comment` — interaction toggles; default **off** (none pre-checked) per guidelines.
- `video_cover_timestamp_ms` — frame to use as cover.
- `brand_content_toggle` — `true` = **Branded Content** ("Paid partnership", promoting a third party). Cannot be combined with `SELF_ONLY`.
- `brand_organic_toggle` — `true` = **Your Brand** ("Promotional content", promoting yourself).
- `is_aigc` — AI-generated content flag.

**Response:**
```json
{
  "data": { "publish_id": "v_pub_...", "upload_url": "https://...  (FILE_UPLOAD only, valid 1h)" },
  "error": { "code": "ok", "message": "", "log_id": "..." }
}
```

### 6.2 Upload the bytes (FILE_UPLOAD only)

PUT chunks **sequentially** to `upload_url` ([Media transfer guide](https://developers.tiktok.com/doc/content-posting-api-media-transfer-guide)):
```
PUT {upload_url}
Content-Type: video/mp4
Content-Length: {bytes_in_this_chunk}
Content-Range: bytes {first}-{last}/{video_size}
<binary chunk>
```
Chunking rules (verbatim limits):
- Each chunk **≥ 5 MB and ≤ 64 MB**, **except the final chunk** which may exceed `chunk_size` **up to 128 MB**.
- `total_chunk_count` = `floor(video_size / chunk_size)`. Minimum **1**, maximum **1000** chunks.
- Files **< 5 MB** must be uploaded **whole**: `chunk_size = video_size`, `total_chunk_count = 1`, single PUT returns **HTTP 201**.
- `Content-Range` is 0-indexed inclusive, e.g. `bytes 0-30567099/30567100`.

For `PULL_FROM_URL`, skip this step — TikTok downloads from `video_url` itself (domain must be verified; see [§9](#9-rate-limits--gotchas)).

### 6.3 Poll status

```
POST /v2/post/publish/status/fetch/
Authorization: Bearer {access_token}
Content-Type: application/json; charset=UTF-8
{ "publish_id": "v_pub_..." }
```
`data.status` enum:
- `PROCESSING_UPLOAD` — FILE_UPLOAD in progress.
- `PROCESSING_DOWNLOAD` — PULL_FROM_URL download in progress.
- `SEND_TO_USER_INBOX` — *Upload mode* only: draft delivered to creator's inbox.
- `PUBLISH_COMPLETE` — posted (Direct Post) / creator finished editing.
- `FAILED` — see `fail_reason`.

Other `data` fields: `fail_reason`, `publicaly_available_post_id` (list — returned **only** once a public post clears moderation; *note TikTok's spelling typo "publicaly"*), `uploaded_bytes`, `downloaded_bytes`.

> Prefer **webhooks** ([§8](#8-webhooks)) for the terminal outcome; poll as a fallback. Status fetch is rate-limited to **30 req/min per access_token**.

### 6.4 Photo / carousel post (supported)

One unified endpoint for images ([Photo post ref](https://developers.tiktok.com/doc/content-posting-api-reference-photo-post)):
```
POST /v2/post/publish/content/init/
Authorization: Bearer {access_token}
Content-Type: application/json; charset=UTF-8
{
  "media_type": "PHOTO",
  "post_mode": "DIRECT_POST",
  "post_info": {
    "title": "Carousel title (≤90 runes)",
    "description": "Body text (≤4000 runes)",
    "privacy_level": "SELF_ONLY",
    "disable_comment": false,
    "auto_add_music": true,
    "brand_content_toggle": false,
    "brand_organic_toggle": false
  },
  "source_info": {
    "source": "PULL_FROM_URL",
    "photo_cover_index": 0,
    "photo_images": [
      "https://verified-domain.agencios.com/img/1.jpg",
      "https://verified-domain.agencios.com/img/2.jpg"
    ]
  }
}
```
- `post_mode`: `DIRECT_POST` (needs `video.publish`) or `MEDIA_UPLOAD` (draft to inbox, needs `video.upload`).
- `media_type`: `PHOTO`.
- `photo_images`: **up to 35** publicly accessible URLs. **JPEG/WEBP only — PNG is rejected.** Photos use `PULL_FROM_URL` (not chunked upload). Same domain-verification rule applies.
- `photo_cover_index`: 0-based index of the cover image.
- Poll the same `status/fetch/` endpoint with the returned `publish_id`.

### 6.5 Unaudited-app limitation (recap)

- **Privacy is forced to `SELF_ONLY`** for all posts. `privacy_level_options` from creator_info will reflect this — do not hardcode public.
- **≤ 5 distinct users may post per 24h.**
- To make content public later, the **creator** must (a) set their account public and (b) change each post's audience to "Everyone" inside TikTok.
- Lift these limits only by passing the **app audit** ([§2.7](#27-submit-for-review-only-when-going-to-production)).

---

## 7. Analytics flow — Display API

Read-only metrics for connected accounts. Base URL `https://open.tiktokapis.com`. ([Display API overview](https://developers.tiktok.com/doc/display-api-overview), [Get started](https://developers.tiktok.com/doc/display-api-get-started))

### 7.1 Account stats — `/v2/user/info/`

```
GET https://open.tiktokapis.com/v2/user/info/?fields=open_id,union_id,avatar_url,display_name,username,is_verified,bio_description,profile_deep_link,follower_count,following_count,likes_count,video_count
Authorization: Bearer {access_token}
```
Fields by scope:
- **`user.info.basic`**: `open_id`, `union_id`, `avatar_url`, `avatar_url_100`, `avatar_large_url`, `display_name`.
- **`user.info.profile`**: `bio_description`, `profile_deep_link`, `is_verified`, `username`.
- **`user.info.stats`** *(account analytics)*: `follower_count`, `following_count`, `likes_count`, `video_count`.

Only request fields whose scopes were granted, or the call errors.

### 7.2 Video metrics — `/v2/video/list/` (and `/v2/video/query/`)

```
POST https://open.tiktokapis.com/v2/video/list/?fields=id,title,video_description,duration,cover_image_url,share_url,embed_link,create_time,like_count,comment_count,share_count,view_count
Authorization: Bearer {access_token}
Content-Type: application/json
{ "max_count": 20, "cursor": 0 }
```
- Scope: **`video.list`**. `max_count` default 10, **max 20**. Pagination via `cursor` (a UTC Unix **milliseconds** timestamp) + `has_more` in the response; pass `response.cursor` to fetch the next page.
- **Per-video engagement fields** (the analytics payload): `like_count`, `comment_count`, `share_count`, `view_count` (plus `id`, `create_time`, `cover_image_url` (6h TTL), `share_url`, `video_description`, `duration`, `height`, `width`, `title`, `embed_html`, `embed_link`).
- `/v2/video/query/` fetches the same fields **filtered by a list of video `id`s** — use it to refresh metrics on videos you already track.

### 7.3 What TikTok exposes vs. not (via these APIs)

- **Exposed:** account totals (`follower_count`, `following_count`, `likes_count`, `video_count`) and per-video **likes / comments / shares / views**.
- **Only public videos** are visible through `video.list`/`video.query`. `SELF_ONLY` (unaudited) posts won't surface here for analytics.
- **NOT exposed** by the Display/Content APIs: watch-time, completion rate, traffic sources, audience demographics, reach/impressions breakdowns, follower-growth time series, or other "TikTok Analytics dashboard"–style metrics. Those live in the **Creator/Business analytics products** (TikTok Business / Marketing API), not the Display API. Don't promise dashboard parity.

---

## 8. Webhooks

Optional but preferred over polling for post outcomes. Configure the **webhook callback URL** (HTTPS) under the app's Webhooks config in the portal. ([Webhooks overview](https://developers.tiktok.com/doc/webhooks-overview), [Events](https://developers.tiktok.com/doc/webhooks-events), [Verification](https://developers.tiktok.com/doc/webhooks-verification))

**Envelope (top-level fields):**
```json
{
  "event": "post.publish.complete",
  "client_key": "awxxxx",
  "create_time": 1733000000,
  "user_openid": "_open_id_",
  "content": "{\"publish_id\":\"v_pub_...\",\"...\":\"...\"}"   // content is a JSON *string* — parse it
}
```

**Relevant events** (Content Posting events were renamed from the legacy `video.*` set):
- `post.publish.complete` — post finished (was `video.publish.complete`).
- `post.publish.failed` — post failed (was `video.upload.failed`).
- `post.publish.inbox_delivered` — Upload-mode draft delivered to creator inbox.
- `post.publish.publicly_available` / `post.publish.no_longer_available` — public visibility changes after moderation.
- `authorization.removed` — user de-authorized your app. `content.reason` int: `0` unknown, `1` user disconnects, `2` account deleted, `3` age changed, `4` account banned, `5` developer revoke. **On this event, mark the `SocialAccount` revoked.**

> Event names in the Content Posting set are still settling in the docs; treat the `post.publish.*` family as the current names and handle the legacy `video.publish.completed` / `video.upload.failed` as aliases if you receive them.

**Delivery rules:** HTTPS only; **respond 200 immediately**; retries with exponential backoff for **up to 72h**; events may be **delivered more than once → make handlers idempotent** (dedupe on `publish_id` + `event`).

**Signature verification** (do this before processing):
- Header: `TikTok-Signature: t=1633174587,s=<hex>`.
- Split on `,` then `=` to get `t` and `s`.
- `signed_payload = "{t}" + "." + raw_request_body`.
- `expected = HMAC_SHA256(key = client_secret, message = signed_payload)` (hex).
- Constant-time compare `expected` to `s`. Reject if mismatched (and optionally reject stale `t`).

---

## 9. Rate limits & gotchas

- **Audit is the gate.** Until approved: `SELF_ONLY` only, ≤5 users/24h. Reviewers explicitly check that your UI **shows creator nickname + avatar**, **lets the user pick a privacy level**, and leaves **interaction toggles unchecked by default**. Provide demo videos of the full flow.
- **Creator info is mandatory before every post** — and it dictates allowed `privacy_level_options` and `max_video_post_duration_sec`. Never hardcode `PUBLIC_TO_EVERYONE`.
- **Branded/commercial content:** `brand_content_toggle` = "Branded Content" ("Paid partnership", third-party). `brand_organic_toggle` = "Your Brand" ("Promotional content", self). **`brand_content_toggle` cannot be used with `SELF_ONLY`** — so for unaudited apps, keep branded content off. At least one toggle must be set if the disclosure switch is enabled.
- **No watermarks/logos.** Adding promotional watermarks/logos to creators' content is prohibited and is a review failure.
- **`PULL_FROM_URL` domain verification.** The media URL's domain (or exact URL prefix) must be **verified** in URL properties; HTTPS, **no redirects**. Prefix matching is **exact** — `https://x.com/videos/user/` covers `.../user/123.mp4` but **not** `.../2023/user/123.mp4`. Presigned S3/Google Drive/temporary CDN links fail with `url_ownership_unverified` unless that exact domain is verified.
- **Photo formats:** JPEG/WEBP only; **PNG rejected**. Up to 35 images.
- **Upload URL TTL:** the FILE_UPLOAD `upload_url` is valid **1 hour**.
- **Chunk limits:** 5 MB ≤ chunk ≤ 64 MB (final up to 128 MB); 1–1000 chunks; sequential; `<5 MB` whole-file (HTTP 201).
- **Rate limits:** Direct Post init ≈ **6 req/min per access_token**; `status/fetch` ≈ **30 req/min**; user-info/video-list have their own caps. Over-limit → **HTTP 429 `rate_limit_exceeded`** (sliding 1-min window). ([Rate limit doc](https://developers.tiktok.com/doc/tiktok-api-v2-rate-limit))
- **Token rotation:** refresh response may return a **new** `refresh_token` — persist it (see [§4.3](#43-refresh--grant_typerefresh_token-with-rotation)).
- **`cover_image_url` TTL is 6h**; don't store it long-term — re-fetch or re-host.
- **Spelling:** the success post id field is `publicaly_available_post_id` (TikTok's typo) — match it exactly.

---

## 10. Testing checklist

- [ ] Credentials present: `Rails.application.credentials.tiktok[:client_key]` / `[:client_secret]` resolve.
- [ ] OAuth: authorize URL opens, callback receives `code` + matching `state`; token exchange persists a `SocialAccount` with both tokens + expiries + scopes.
- [ ] Refresh: forcing `access_token_expired?` triggers `Operations::TikTok::RefreshAccessToken`; **new refresh_token is stored** when returned.
- [ ] `creator_info/query` returns nickname/avatar and `privacy_level_options`; UI renders them.
- [ ] Sandbox account is set **private**; Direct Post of a small (<5 MB) video succeeds whole-file (HTTP 201) → status reaches `PUBLISH_COMPLETE`.
- [ ] Multi-chunk video (e.g. 30 MB, 10 MB chunks → 3 chunks) uploads sequentially with correct `Content-Range`; status completes.
- [ ] `PULL_FROM_URL` from a **verified** domain succeeds; an unverified domain fails with `url_ownership_unverified`.
- [ ] Photo carousel (JPEG, ≤35) posts; PNG is rejected as expected.
- [ ] All sandbox posts are `SELF_ONLY`; attempting `PUBLIC_TO_EVERYONE` is rejected/clamped.
- [ ] Analytics: `user/info` returns stats; `video/list` returns `like_count`/`comment_count`/`share_count`/`view_count` with pagination.
- [ ] Webhook endpoint returns 200 fast; **signature verified**; handlers idempotent; `authorization.removed` marks `SocialAccount.revoked_at`.
- [ ] 429 handling: Sidekiq job retries/backoff on `rate_limit_exceeded`.
- [ ] Production submission: demo videos show full flow; URL properties verified; scopes justified.

---

## API reference quick table

| Operation | Method + endpoint (base `https://open.tiktokapis.com`, auth host `https://www.tiktok.com`) | Scope | `Vendors::TikTok::Actions::*` | Touches `SocialAccount` |
|---|---|---|---|---|
| Authorize | `GET tiktok.com/v2/auth/authorize/` | (requested set) | `BuildAuthorizeUrl` | — (writes `state` to session) |
| Token exchange | `POST /v2/oauth/token/` (`authorization_code`) | — | `ExchangeCode` | create: `access_token`, `refresh_token`, `*_expires_at`, `provider_open_id`, `scopes` |
| Refresh token | `POST /v2/oauth/token/` (`refresh_token`) | — | `RefreshToken` | update: `access_token`, `refresh_token`, `*_expires_at` |
| Revoke | `POST /v2/oauth/revoke/` | — | `RevokeToken` | set `revoked_at` |
| Creator info | `POST /v2/post/publish/creator_info/query/` | `video.publish`/`video.upload` | `QueryCreatorInfo` | reads `access_token` |
| Video init | `POST /v2/post/publish/video/init/` | `video.publish` (Direct) / `video.upload` (Upload) | `PublishVideo` (init) | reads `access_token` |
| Upload chunk | `PUT {upload_url}` | — | `PublishVideo` (transfer) | — |
| Photo/carousel init | `POST /v2/post/publish/content/init/` | `video.publish`/`video.upload` | `PublishPhoto` | reads `access_token` |
| Post status | `POST /v2/post/publish/status/fetch/` | `video.publish`/`video.upload` | `FetchPublishStatus` | reads `access_token` |
| Account stats | `GET /v2/user/info/?fields=...` | `user.info.basic`/`.profile`/`.stats` | `FetchUserInfo` | reads `access_token`; may update `display_name`/`username`/`avatar_url` |
| Video metrics | `POST /v2/video/list/?fields=...` | `video.list` | `ListVideos` | reads `access_token` |
| Video metrics by id | `POST /v2/video/query/?fields=...` | `video.list` | `QueryVideos` | reads `access_token` |

---

## Appendix — Rails wiring sketch (`agencios` conventions)

> Vendor `Client` = raw HTTP only (no domain logic, no DB). `Actions::<Verb>` delegate to the client and are the call sites. Domain side effects + token persistence/rotation live in `app/services/operations/`. Background work runs on Sidekiq.

**Client (raw HTTP)** — `app/services/vendors/TikTok/client.rb`:
```ruby
module Vendors
  module TikTok
    class Client
      API   = "https://open.tiktokapis.com"
      OAUTH = "https://www.tiktok.com"

      def initialize(access_token: nil)
        @access_token = access_token
      end

      # --- OAuth ---
      def exchange_code(code:, redirect_uri:, code_verifier: nil)
        form_post("#{API}/v2/oauth/token/", {
          client_key:    creds[:client_key],
          client_secret: creds[:client_secret],
          code:, grant_type: "authorization_code", redirect_uri:, code_verifier:
        }.compact)
      end

      def refresh(refresh_token:)
        form_post("#{API}/v2/oauth/token/", {
          client_key:    creds[:client_key],
          client_secret: creds[:client_secret],
          grant_type: "refresh_token", refresh_token:
        })
      end

      # --- Content Posting ---
      def query_creator_info = json_post("#{API}/v2/post/publish/creator_info/query/", {})
      def init_video(post_info:, source_info:)
        json_post("#{API}/v2/post/publish/video/init/", { post_info:, source_info: })
      end
      def init_content(payload) = json_post("#{API}/v2/post/publish/content/init/", payload)
      def fetch_status(publish_id:) = json_post("#{API}/v2/post/publish/status/fetch/", { publish_id: })
      def upload_chunk(upload_url:, bytes:, content_range:, mime: "video/mp4")
        # PUT with Content-Range / Content-Length / Content-Type
      end

      # --- Display ---
      def user_info(fields:)  = json_get("#{API}/v2/user/info/", fields:)
      def video_list(fields:, max_count: 20, cursor: 0)
        json_post("#{API}/v2/video/list/?fields=#{fields}", { max_count:, cursor: })
      end

      private
      def creds = Rails.application.credentials.tiktok
      # form_post / json_post / json_get add Authorization: Bearer @access_token, parse JSON, raise typed errors on error.code != "ok"
    end
  end
end
```

**Example action** — `app/services/vendors/TikTok/actions/publish_video.rb`:
```ruby
module Vendors
  module TikTok
    module Actions
      class PublishVideo < Operations::Base
        # Vendors::TikTok::Actions::PublishVideo.call(social_account:, video:, post_info:)
        def initialize(social_account:, video:, post_info:)
          @social_account = social_account
          @video, @post_info = video, post_info
        end

        def call
          client = Vendors::TikTok::Client.new(access_token: @social_account.access_token)
          init = client.init_video(post_info: @post_info, source_info: source_info)
          publish_id, upload_url = init.dig("data", "publish_id"), init.dig("data", "upload_url")
          transfer_chunks(client, upload_url) if upload_url   # FILE_UPLOAD path
          publish_id
        end

        private
        def source_info
          { source: "FILE_UPLOAD", video_size: @video.byte_size,
            chunk_size: 10_000_000, total_chunk_count: [@video.byte_size / 10_000_000, 1].max }
        end
        # transfer_chunks: sequential PUTs with Content-Range
      end
    end
  end
end
```

**Operations** (domain side effects, Sidekiq-driven):
- `Operations::TikTok::ConnectAccount` — calls `Actions::ExchangeCode`, then `Actions::FetchUserInfo`, **creates/updates the `SocialAccount`**.
- `Operations::TikTok::RefreshAccessToken` — calls `Actions::RefreshToken`, **persists rotated tokens** (overwrite both + expiries). Call this from a `before`-hook/guard whenever `social_account.access_token_expired?`.
- `Operations::TikTok::PublishPost` — guards token freshness, runs `QueryCreatorInfo` (validates privacy/duration), calls `PublishVideo`/`PublishPhoto`, persists a local `Post` with `publish_id`, then enqueues `TikTok::PollPublishStatusJob` (or relies on the webhook).
- `Operations::TikTok::HandleWebhook` — verifies signature, dedupes, updates `Post`/`SocialAccount` (incl. `authorization.removed → revoked_at`).
- `Operations::TikTok::SyncAnalytics` — periodic Sidekiq job; `FetchUserInfo` + `ListVideos`, upserts metrics.

---

### Sources
- Content Posting API — Get started: https://developers.tiktok.com/doc/content-posting-api-get-started
- Direct Post reference: https://developers.tiktok.com/doc/content-posting-api-reference-direct-post
- Photo Post reference: https://developers.tiktok.com/doc/content-posting-api-reference-photo-post
- Get post status: https://developers.tiktok.com/doc/content-posting-api-reference-get-video-status
- Media transfer guide (chunking + PULL_FROM_URL verification): https://developers.tiktok.com/doc/content-posting-api-media-transfer-guide
- Content sharing guidelines (audit, disclosure, watermark, unaudited limits): https://developers.tiktok.com/doc/content-sharing-guidelines
- Display API overview: https://developers.tiktok.com/doc/display-api-overview
- Display API get started: https://developers.tiktok.com/doc/display-api-get-started
- Get user info: https://developers.tiktok.com/doc/tiktok-api-v2-get-user-info
- List videos: https://developers.tiktok.com/doc/tiktok-api-v2-video-list
- Video object: https://developers.tiktok.com/doc/tiktok-api-v2-video-object
- Scopes overview: https://developers.tiktok.com/doc/scopes-overview
- OAuth / token management: https://developers.tiktok.com/doc/oauth-user-access-token-management
- Create an app: https://developers.tiktok.com/doc/getting-started-create-an-app
- Sandbox mode: https://developers.tiktok.com/blog/introducing-sandbox
- Webhooks overview / events / verification: https://developers.tiktok.com/doc/webhooks-overview · https://developers.tiktok.com/doc/webhooks-events · https://developers.tiktok.com/doc/webhooks-verification
- Rate limits: https://developers.tiktok.com/doc/tiktok-api-v2-rate-limit
- Changelog: https://developers.tiktok.com/doc/changelog
