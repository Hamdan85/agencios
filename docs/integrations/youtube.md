# YouTube Data API v3 + Analytics Integration Guide (2025–2026)

> **Purpose.** Two audiences in one doc.
> 1. A **browser-operating Claude agent** ("Claude Chrome extension") that needs an exact, click-by-click path through the Google Cloud console.
> 2. A **backend engineer** building the integration into the Rails 8.1 app **`agencios`** with its `Vendors::Youtube` / `Operations` / `SocialAccount` conventions.
>
> Anything labelled **[CLICKPATH]** is for the browser agent. Anything labelled **[BACKEND]** is the Rails code plan.
>
> **Freshness note (verify against revision history before shipping).** The single biggest recent change: **`videos.insert` quota cost dropped from ~1600 units to ~100 units on 2025-12-04** ([YouTube Data API revision history](https://developers.google.com/youtube/v3/revision_history)). Most older blog posts still say 1600 — they are stale. The default daily quota of **10,000 units is unchanged**.

---

## 0. What you'll build

A workspace-scoped YouTube integration that can:

- **Authenticate** a YouTube channel owner via OAuth 2.0 (authorization-code flow, offline access → long-lived refresh token).
- **Upload videos** (regular + Shorts) via the **resumable upload protocol** (`videos.insert`).
- **Set a custom thumbnail** (`thumbnails.set`).
- **Read analytics**: per-channel time-series (`youtubeAnalytics.reports.query`) and lifetime channel stats (`channels.list?part=statistics`).
- Optionally **receive push notifications** of new uploads via **PubSubHubbub** (Atom feed).

**Rails shape (agencios conventions):**

| Concern | Where it lives |
|---|---|
| HTTP/SDK calls to Google | `app/services/vendors/youtube/client.rb` |
| One verb per operation | `app/services/vendors/youtube/actions/<verb>.rb` → `Vendors::Youtube::Actions::UploadVideo.call(...)` |
| Side effects (DB writes, token refresh, orchestration) | `app/services/operations/youtube/*` |
| OAuth tokens (encrypted), `belongs_to :workspace` | `SocialAccount` model |
| `client_id` / `client_secret` | Rails encrypted credentials — shared `google:` block |
| Long-running uploads | Sidekiq jobs |

```
agencios/
  app/
    models/social_account.rb
    services/
      vendors/youtube/
        client.rb
        actions/
          authorize_url.rb          # build consent URL
          exchange_code.rb          # code -> tokens
          refresh_access_token.rb   # refresh_token -> access_token
          upload_video.rb           # videos.insert (resumable)
          set_thumbnail.rb          # thumbnails.set
          query_analytics.rb        # youtubeAnalytics.reports.query
          channel_stats.rb          # channels.list (statistics)
          subscribe_push.rb         # PubSubHubbub subscribe
      operations/youtube/
        connect_account.rb          # persist tokens on SocialAccount
        ensure_fresh_token.rb       # refresh if expiring, persist
        publish_video.rb            # orchestrates upload + thumbnail + persist video id
    jobs/youtube/
      publish_video_job.rb
```

---

## 1. Accounts & prerequisites

You need three things before touching code:

1. **A Google account** that you control (ideally a dedicated "ops" account, not a personal one) — it will own the Cloud project and the OAuth consent screen branding.
2. **A YouTube channel** on the Google account you'll actually upload to. The channel must exist (create it at youtube.com → your avatar → *Create a channel*). The OAuth tokens are bound to whichever **channel** the consenting user picks at the consent screen, not to the project.
3. **A Google Cloud project** (created in §2) with billing not strictly required for YouTube Data API, but recommended for raising quotas later.

> **Important channel nuance.** If the consenting Google account has access to multiple channels/Brand Accounts, the OAuth consent flow lets the user choose which channel to grant. `channel==MINE` in Analytics and `videos.insert` then operate on *that* channel. Persist the resolved channel id (from `channels.list?part=id&mine=true`) on the `SocialAccount` so you never guess.

---

## 2. Create the Google Cloud project + enable APIs

> **Console UI changed in 2024–2025.** What used to be "APIs & Services → OAuth consent screen" is now **"Google Auth Platform"** with four sub-tabs: **Branding**, **Audience**, **Clients**, **Data Access** ([new-UI walkthrough](https://var.gg/en/blog/gcp-oauth-consent-client-id), [Manage OAuth App Branding](https://support.google.com/cloud/answer/15549049)). The clickpath below reflects the current UI.

### [CLICKPATH] 2.1 — Create the project

1. Go to `https://console.cloud.google.com/`.
2. Top bar → **project picker dropdown** (left of the search box) → **New project**.
3. **Name**: `agencios-youtube` (or similar). Leave org/location as-is unless you have a Workspace org. Click **Create**.
4. Wait for the notification, then **select the new project** in the project picker so the rest of the steps apply to it.

### [CLICKPATH] 2.2 — Enable the two APIs

1. Go to `https://console.cloud.google.com/apis/library` (or nav menu → **APIs & Services → Library**).
2. Search **"YouTube Data API v3"** → click the result → **Enable**.
3. Back to Library, search **"YouTube Analytics API"** → click → **Enable**.
   - (Optional) If you'll later pull bulk CSV reports, also enable **"YouTube Reporting API"** — different from the Analytics API; not needed for `reports.query`.

Direct enable links (browser agent can navigate straight to these and click **Enable**):
- YouTube Data API v3: `https://console.cloud.google.com/apis/library/youtube.googleapis.com`
- YouTube Analytics API: `https://console.cloud.google.com/apis/library/youtubeanalytics.googleapis.com`

### [CLICKPATH] 2.3 — Configure the OAuth consent screen ("Google Auth Platform")

1. Nav menu → **APIs & Services → OAuth consent screen** (this lands on **Google Auth Platform**). Direct: `https://console.cloud.google.com/apis/credentials/consent`.
2. If prompted to "Get started", fill **App name**, **User support email**, then continue.
3. **Audience** tab → choose **User type**:
   - **External** (almost always — your users are outside your Google org). This starts in **Testing** mode.
   - **Internal** only if every user is in your Google Workspace org.
4. **Branding** tab → fill **App name**, **User support email**, **App logo** (optional but required for verification), **Application home page**, **Privacy policy URL**, **Terms of service URL**, and **Authorized domains** (e.g. `agencios.com`). These must be real and reachable for verification (§3).
5. **Audience** tab → under **Test users**, click **Add users** and add every Google account email you'll test with **while in Testing mode** (only test users can authorize an unverified app; cap is 100).

### [CLICKPATH] 2.4 — Add scopes (Data Access tab)

1. **Data Access** tab → **Add or remove scopes**.
2. In the panel, paste/select the four scopes from §3. (Search by the scope URL or by API name; you can paste the full scope strings into the "manually add scopes" box.)
3. **Update** → **Save**.

### [CLICKPATH] 2.5 — Create the OAuth client (Web application)

1. **Clients** tab (or **APIs & Services → Credentials**) → **Create credentials → OAuth client ID**. Direct: `https://console.cloud.google.com/apis/credentials`.
2. **Application type**: **Web application**.
3. **Name**: `agencios-web`.
4. **Authorized JavaScript origins** — add your front-end origins (only if you ever do browser-side token flows; for a pure server-side flow you can leave this empty):
   - `https://app.agencios.com`
   - `http://localhost:3000` (dev)
5. **Authorized redirect URIs** — these MUST exactly match the `redirect_uri` your Rails app sends (path + scheme + host, no trailing slash mismatch):
   - `https://app.agencios.com/oauth/youtube/callback`
   - `http://localhost:3000/oauth/youtube/callback` (dev)
6. **Create** → a modal shows **Client ID** and **Client secret**. Copy both (you can also **Download JSON**). These go into Rails credentials (§5), **never** into `.env` or the repo.

---

## 3. Scopes + consent-screen verification

### Scopes you request

| Scope | Why | Sensitivity |
|---|---|---|
| `https://www.googleapis.com/auth/youtube.upload` | `videos.insert`, `thumbnails.set` | **Sensitive** |
| `https://www.googleapis.com/auth/youtube.readonly` | `channels.list`, `videos.list` (read) | **Sensitive** |
| `https://www.googleapis.com/auth/yt-analytics.readonly` | `youtubeAnalytics.reports.query` (non-monetary) | **Sensitive** |
| `https://www.googleapis.com/auth/youtube.force-ssl` | Full manage (edit/delete video, captions, comments) — request **only if you need write-beyond-upload** | **Sensitive** |

Source: [Using OAuth 2.0 for Web Server Applications](https://developers.google.com/youtube/v3/guides/auth/server-side-web-apps), [OAuth 2.0 Scopes for Google APIs](https://developers.google.com/identity/protocols/oauth2/scopes#youtube).

> **Minimize.** Request the smallest set that delivers the feature. For "upload + read own analytics" you need only `youtube.upload` + `youtube.readonly` + `yt-analytics.readonly`. Add `youtube.force-ssl` **only** if you later edit/delete videos or manage comments — it raises review scrutiny. (`youtube.force-ssl` also covers reads and uploads, so you could collapse to it alone, but a broad scope is harder to get verified — prefer narrow.)
> For revenue metrics you'd also need `https://www.googleapis.com/auth/yt-analytics-monetary.readonly` — out of scope here.

### Verification (the part that bites you)

All YouTube scopes above are **Sensitive** (none are "Restricted" — that tier is reserved for Gmail/Drive-style scopes and requires an annual third-party security assessment, which YouTube scopes do **not**). Implications ([Sensitive scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification), [Unverified apps](https://support.google.com/cloud/answer/7454865), [Verification requirements](https://support.google.com/cloud/answer/13464321)):

- **While in Testing mode**: only the **test users** you added (§2.3) can authorize, the app shows an "unverified app" warning, and **refresh tokens expire after 7 days**. This is fine for development.
- **To go to Production**: publish the app (**Audience → Publish app**) and submit for **verification**. Sensitive-scope verification requires:
  - **Brand verification** first (app name, logo, support email, homepage, privacy policy, ToS, verified domain ownership). Typically a few business days.
  - A scope **justification** for each sensitive scope.
  - A **demonstration video** uploaded to YouTube (set **Unlisted**) that shows a user granting consent and the app actually using each granted scope. Link it in the verification form.
  - **Domain ownership** verified in Search Console for every authorized domain.
- Timeline: brand verification ~2–3 business days; full sensitive review can take **days to a few weeks**. Plan launch around it.

> **[CLICKPATH] Publish + verify:** Google Auth Platform → **Audience** → **Publish app** → confirm. Then **Verification Center** (link appears once sensitive scopes are present) → fill scope justifications, paste the unlisted demo-video URL, submit.

---

## 4. OAuth flow (authorization-code, offline)

Reference: [Using OAuth 2.0 for Web Server Applications](https://developers.google.com/youtube/v3/guides/auth/server-side-web-apps).

### 4.1 Build the authorization URL → redirect the user

**Endpoint:** `GET https://accounts.google.com/o/oauth2/v2/auth`

| Param | Value | Notes |
|---|---|---|
| `client_id` | from credentials | |
| `redirect_uri` | `https://app.agencios.com/oauth/youtube/callback` | must exactly match a registered URI |
| `response_type` | `code` | |
| `scope` | space-delimited list from §3 | URL-encoded |
| `access_type` | `offline` | **required to get a refresh token** |
| `prompt` | `consent` | **forces a refresh token to be returned** (Google omits it on re-consent otherwise) |
| `include_granted_scopes` | `true` | incremental auth |
| `state` | random CSRF token | store in session, validate on callback |

Example (line-wrapped for readability):
```
https://accounts.google.com/o/oauth2/v2/auth
  ?client_id=YOUR_CLIENT_ID
  &redirect_uri=https%3A%2F%2Fapp.agencios.com%2Foauth%2Fyoutube%2Fcallback
  &response_type=code
  &scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fyoutube.upload%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fyoutube.readonly%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fyt-analytics.readonly
  &access_type=offline
  &prompt=consent
  &include_granted_scopes=true
  &state=RANDOM_CSRF
```

### 4.2 Exchange the code for tokens

After Google redirects back with `?code=...&state=...`, validate `state`, then:

**Endpoint:** `POST https://oauth2.googleapis.com/token` (form-encoded body)

| Param | Value |
|---|---|
| `code` | the authorization code |
| `client_id` | from credentials |
| `client_secret` | from credentials |
| `redirect_uri` | same as step 4.1 |
| `grant_type` | `authorization_code` |

**Response:**
```json
{
  "access_token": "ya29....",
  "expires_in": 3599,
  "refresh_token": "1//0g....",   // present ONLY with access_type=offline + prompt=consent
  "scope": "https://www.googleapis.com/auth/youtube.upload ...",
  "token_type": "Bearer"
}
```

Immediately call `channels.list?part=id,snippet&mine=true` to resolve and store the **channel id** + name on the `SocialAccount`.

### 4.3 Refresh the access token

Access tokens last ~1 hour. Refresh:

**Endpoint:** `POST https://oauth2.googleapis.com/token`

| Param | Value |
|---|---|
| `client_id` | from credentials |
| `client_secret` | from credentials |
| `refresh_token` | stored token |
| `grant_type` | `refresh_token` |

Returns a fresh `access_token` + `expires_in` (no new `refresh_token`). Persist `access_token` + computed `token_expires_at`.

> **Refresh-token expiry gotchas:** (a) in **Testing** mode refresh tokens die after **7 days** — publish to fix; (b) a refresh token is revoked if the user removes app access, you exceed ~50 live refresh tokens per (user, client), or it's unused for ~6 months. Handle `invalid_grant` by marking the `SocialAccount` as needing re-auth and prompting the user.

---

## 5. Store credentials

### [BACKEND] Rails encrypted credentials

```bash
EDITOR=nano bin/rails credentials:edit
```
YouTube uses the **shared Google OAuth client** — the same `google:` block that backs Google
sign-in and Calendar. There is **no** separate `youtube:` block; just register this YouTube
flow's redirect URI (`/auth/youtube/callback`) on that one OAuth client in Google Cloud.
```yaml
google:
  client_id: "xxxx.apps.googleusercontent.com"
  client_secret: "GOCSPX-xxxx"
```
Read via `Rails.application.credentials.dig(:google, :client_id)` (ENV fallback `GOOGLE_CLIENT_ID` /
`GOOGLE_CLIENT_SECRET`). The `redirect_uri` is built in code from `SystemConfig.app_host`, not stored
here. **Never** put these in `.env` or commit them. See [`docs/CREDENTIALS.md`](../CREDENTIALS.md).

### [BACKEND] `SocialAccount` model + migration

```ruby
# db/migrate/XXXX_create_social_accounts.rb
class CreateSocialAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :social_accounts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :provider, null: false, default: "youtube"   # string enum-friendly
      t.string  :external_channel_id                          # YouTube channel id (UC...)
      t.string  :channel_title

      # Encrypted OAuth material
      t.text    :access_token                                 # encrypted
      t.text    :refresh_token                                # encrypted
      t.datetime :token_expires_at
      t.string  :scopes                                       # space-delimited granted scopes

      t.string  :status, null: false, default: "connected"   # connected | needs_reauth | revoked
      t.datetime :last_synced_at
      t.timestamps
    end
    add_index :social_accounts, [:workspace_id, :provider, :external_channel_id], unique: true
  end
end
```

```ruby
# app/models/social_account.rb
class SocialAccount < ApplicationRecord
  belongs_to :workspace

  encrypts :access_token
  encrypts :refresh_token

  enum :provider, { youtube: "youtube" }, prefix: true
  enum :status, { connected: "connected", needs_reauth: "needs_reauth", revoked: "revoked" }, prefix: true

  def token_expired?(skew: 60.seconds)
    token_expires_at.nil? || token_expires_at <= Time.current + skew
  end
end
```

> `encrypts` uses Rails' built-in Active Record Encryption — ensure `active_record_encryption` keys exist in credentials (`bin/rails db:encryption:init` to generate). This keeps tokens encrypted at rest.

---

## 6. Publishing flow — `videos.insert` resumable upload

References: [Resumable Uploads](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol), [Videos: insert](https://developers.google.com/youtube/v3/docs/videos/insert), [Upload a Video](https://developers.google.com/youtube/v3/guides/uploading_a_video).

Use **resumable** for any file > 5 MB (i.e. every real video). Simple upload has no recovery.

### 6.1 The metadata body (`snippet` + `status`)

```json
{
  "snippet": {
    "title": "My video title",              // <= 100 chars; no < or >
    "description": "Long description...",     // <= 5000 chars
    "tags": ["agencios", "demo"],             // optional; total <= 500 chars
    "categoryId": "22",                       // string; from videoCategories.list (22 = People & Blogs)
    "defaultLanguage": "pt-BR"
  },
  "status": {
    "privacyStatus": "private",               // "public" | "private" | "unlisted"
    "publishAt": "2026-07-01T12:00:00Z",      // optional; requires privacyStatus=private (scheduled)
    "selfDeclaredMadeForKids": false,         // REQUIRED to declare COPPA status
    "embeddable": true,
    "license": "youtube",
    "containsSyntheticMedia": false           // set true if AI-generated/altered realistic content
  }
}
```

- **`selfDeclaredMadeForKids`** must be set deliberately — it's the COPPA "made for kids" flag.
- **Scheduled publish**: set `privacyStatus: "private"` + `publishAt` (RFC 3339 UTC).
- Query param **`notifySubscribers`** defaults to `true`; pass `false` for silent/bulk uploads.

### 6.2 Step 1 — initiate the resumable session

```
POST https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status
Authorization: Bearer ACCESS_TOKEN
Content-Type: application/json; charset=UTF-8
Content-Length: <len of JSON body>
X-Upload-Content-Length: <total video size in bytes>
X-Upload-Content-Type: video/*

<the JSON body from 6.1>
```
Response is `200 OK` with the session URI in the **`Location`** header:
```
Location: https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&upload_id=xa298sd_f&part=snippet,status
```
Save that URI.

### 6.3 Step 2 — upload the bytes (whole file or chunked)

Whole file (simplest, fine when you can stream from disk):
```
PUT <session URI>
Authorization: Bearer ACCESS_TOKEN
Content-Length: <total size>
Content-Type: video/*

<binary bytes>
```

Chunked (resilient for huge files): each chunk size **must be a multiple of 256 KB (262144 bytes)** except the last; chunks must be contiguous.
```
PUT <session URI>
Authorization: Bearer ACCESS_TOKEN
Content-Length: 262144
Content-Type: video/*
Content-Range: bytes 0-262143/2000000

<262144 bytes>
```
- `Content-Range: bytes FIRST-LAST/TOTAL` (0-based, inclusive).
- Non-final chunk → `308 Resume Incomplete` (check `Range` header for last accepted byte).
- Final chunk → **`201 Created`** with the full video resource (contains the new **video id**).

### 6.4 Step 3 — resume an interrupted upload

On connection loss or `5xx` (500/502/503/504 → exponential backoff), query status:
```
PUT <session URI>
Authorization: Bearer ACCESS_TOKEN
Content-Length: 0
Content-Range: bytes */2000000
```
→ `308 Resume Incomplete` with `Range: bytes=0-999999` → resume from byte 1000000. A `404` means the session URI expired → restart from §6.2.

### 6.5 Publishing a **Short**

There is **no separate "Shorts" API field**. YouTube auto-classifies a Short by the media itself:
- **Vertical 9:16** aspect ratio (1080×1920 ideal), and
- **Duration ≤ 3 minutes** (the limit was raised from 60s in late 2024 — [YouTube Shorts specs 2025/2026](https://vidiq.com/blog/post/youtube-shorts-vertical-video/)).

So: upload the vertical, ≤3-min file with normal `videos.insert`. **Add `#Shorts` to the title or description** to help classification (especially for desktop/API uploads). That's it — YouTube routes it to the Shorts feed.
References on detection/specs: [Boris FX — Shorts aspect ratio/resolution](https://borisfx.com/blog/best-youtube-short-aspect-ratio-resolution/), [vidIQ Shorts dimensions](https://vidiq.com/blog/post/youtube-shorts-vertical-video/).

### 6.6 Setting a custom thumbnail (`thumbnails.set`)

Reference: [Thumbnails: set](https://developers.google.com/youtube/v3/docs/thumbnails/set).
```
POST https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=VIDEO_ID
Authorization: Bearer ACCESS_TOKEN
Content-Type: image/jpeg            // or image/png, application/octet-stream

<image bytes>
```
- Max **2 MB**; formats jpeg/png. Recommended 1280×720 (16:9), 1920×1080 max.
- Requires a **verified** YouTube account (phone-verified channel) — otherwise `403`. Cost **50 units**.

### [BACKEND] Wiring

- `Vendors::Youtube::Actions::UploadVideo.call(social_account:, file_path:, metadata:)` — runs §6.2–6.4, returns the video id.
- `Vendors::Youtube::Actions::SetThumbnail.call(social_account:, video_id:, image_path:)` — §6.6.
- `Operations::Youtube::PublishVideo.call(workspace:, social_account:, file:, metadata:, thumbnail: nil)` — orchestrates: `EnsureFreshToken` → `UploadVideo` → optional `SetThumbnail` → persist video id / status. **No `create!` of another entity inside this op — delegate to that entity's service if one exists.**
- `Youtube::PublishVideoJob` (Sidekiq) — enqueues the operation off the request cycle; uploads are slow.

```ruby
# app/services/operations/youtube/publish_video.rb (sketch)
module Operations
  module Youtube
    class PublishVideo < Operations::Base
      def call(social_account:, file:, metadata:, thumbnail: nil)
        Operations::Youtube::EnsureFreshToken.call(social_account: social_account)
        video_id = Vendors::Youtube::Actions::UploadVideo.call(
          social_account: social_account, file_path: file, metadata: metadata
        )
        if thumbnail
          Vendors::Youtube::Actions::SetThumbnail.call(
            social_account: social_account, video_id: video_id, image_path: thumbnail
          )
        end
        video_id
      end
    end
  end
end
```

---

## 7. Analytics flow

### 7.1 Time-series via the YouTube Analytics API

References: [reports.query](https://developers.google.com/youtube/analytics/reference/reports/query), [Metrics](https://developers.google.com/youtube/analytics/metrics), [Dimensions](https://developers.google.com/youtube/analytics/dimensions), [Sample requests](https://developers.google.com/youtube/analytics/sample-requests).

**Endpoint:** `GET https://youtubeanalytics.googleapis.com/v2/reports`
**Auth:** `Authorization: Bearer ACCESS_TOKEN` (scope `yt-analytics.readonly`).

| Param | Required | Example |
|---|---|---|
| `ids` | yes | `channel==MINE` (or `channel==UC...`) |
| `startDate` / `endDate` | yes | `2026-01-01` / `2026-06-30` (YYYY-MM-DD) |
| `metrics` | yes | `views,estimatedMinutesWatched,likes,comments,subscribersGained,subscribersLost` |
| `dimensions` | no | `day` (also `month`, `video`, `country`, `deviceType`, ...) |
| `filters` | no | `video==VIDEO_ID;country==BR` |
| `sort` | no | `day` (prefix `-` for desc) |
| `maxResults` / `startIndex` | no | pagination |
| `currency` | no | revenue metrics only |

Common metrics: `views`, `estimatedMinutesWatched`, `averageViewDuration`, `averageViewPercentage`, `likes`, `dislikes`, `comments`, `shares`, `subscribersGained`, `subscribersLost`.

**Example request:**
```
GET https://youtubeanalytics.googleapis.com/v2/reports
  ?ids=channel==MINE
  &startDate=2026-01-01&endDate=2026-06-30
  &metrics=views,estimatedMinutesWatched,likes,comments,subscribersGained
  &dimensions=day
  &sort=day
```
**Response (column-oriented):**
```json
{
  "kind": "youtubeAnalytics#resultTable",
  "columnHeaders": [
    {"name": "day",                    "columnType": "DIMENSION", "dataType": "STRING"},
    {"name": "views",                  "columnType": "METRIC",    "dataType": "INTEGER"},
    {"name": "estimatedMinutesWatched","columnType": "METRIC",    "dataType": "INTEGER"},
    {"name": "likes",                  "columnType": "METRIC",    "dataType": "INTEGER"},
    {"name": "comments",               "columnType": "METRIC",    "dataType": "INTEGER"},
    {"name": "subscribersGained",      "columnType": "METRIC",    "dataType": "INTEGER"}
  ],
  "rows": [
    ["2026-01-01", 1250, 3400, 88, 5, 12],
    ["2026-01-02", 1840, 5010, 120, 9, 20]
  ]
}
```
Rows align to `columnHeaders` by index — map them when serializing for the frontend.

### 7.2 Lifetime channel stats via the Data API

For totals (subscribers, total views, video count) use `channels.list`:
```
GET https://www.googleapis.com/youtube/v3/channels?part=statistics&mine=true
Authorization: Bearer ACCESS_TOKEN     // scope youtube.readonly
```
```json
{ "items": [{ "statistics": {
  "viewCount": "1234567", "subscriberCount": "8910",
  "hiddenSubscriberCount": false, "videoCount": "42"
}}]}
```
Reference: [Channels: list](https://developers.google.com/youtube/v3/docs/channels/list). Cost **1 unit**.

### [BACKEND] Wiring

- `Vendors::Youtube::Actions::QueryAnalytics.call(social_account:, metrics:, dimensions:, start_date:, end_date:, filters: nil)` → returns parsed rows.
- `Vendors::Youtube::Actions::ChannelStats.call(social_account:)` → returns the `statistics` hash.
- An `Operations::Youtube::SyncAnalytics` (optional) persists snapshots and stamps `social_account.last_synced_at`.

---

## 8. Webhooks / PubSubHubbub (push notifications for new uploads)

Use this only if you need to react to uploads on a channel (e.g. confirm a Short went live, or watch an external channel). It is **not required** for the upload/analytics flows above. Reference: [Push Notifications](https://developers.google.com/youtube/v3/guides/push_notifications).

- **Hub:** `https://pubsubhubbub.appspot.com/subscribe`
- **Topic:** `https://www.youtube.com/xml/feeds/videos.xml?channel_id=CHANNEL_ID`
- **Subscribe (POST form):**
  - `hub.callback` = your public HTTPS endpoint (e.g. `https://app.agencios.com/webhooks/youtube`)
  - `hub.topic` = the topic URL above
  - `hub.mode` = `subscribe` (or `unsubscribe`)
  - `hub.verify` = `async` (recommended) or `sync`
- **Verification:** the hub GETs your callback with `hub.challenge` (+ `hub.mode`, `hub.topic`, `hub.lease_seconds`). **Echo back `hub.challenge` with HTTP 200** to confirm.
- **Notifications:** POSTed as **Atom XML** containing `<yt:videoId>` and `<yt:channelId>` (fires on new upload and on title/description edits). Respond 200 quickly; parse async.
- **Lease:** subscriptions expire (`hub.lease_seconds`, ~5–10 days). **Re-subscribe before expiry** (cron/Sidekiq). De-dupe by video id since edits also fire.

### [BACKEND] Wiring
- `Vendors::Youtube::Actions::SubscribePush.call(channel_id:, callback_url:, mode: "subscribe")`.
- A `WebhooksController#youtube`: GET → return `params[:"hub.challenge"]`; POST → enqueue a Sidekiq job to parse the Atom body and react.

---

## 9. Quota & gotchas

References: [Quota calculator](https://developers.google.com/youtube/v3/determine_quota_cost), [Revision history](https://developers.google.com/youtube/v3/revision_history), [Quota & compliance audits](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits).

- **Default: 10,000 units/day** per project (shared across all Data API calls). Resets at midnight Pacific.
- **`videos.insert` ≈ 100 units** (reduced from ~1600 on **2025-12-04** — verify in the calculator; the official limit also caps you at ~100 `videos.insert` calls/day). At ~100 units each, ~100 uploads/day fit in default quota.
- **`thumbnails.set` = 50 units.** **`search.list` = 100 units** (expensive — avoid for lookups; use `channels.list`/`videos.list` at **1 unit** with known ids).
- **`channels.list` / `videos.list` = 1 unit.** Read parts are cheap; prefer them.
- **YouTube Analytics API has its own quota**, separate from the Data API's 10,000 units (queries are rate-limited, not unit-priced the same way) — don't conflate the two budgets.
- **Quota increase:** there's no self-service purchase. Submit the **YouTube API Services — Audit and Quota Extension form** and pass Google's compliance/audit review (can take weeks). Build for the default first.
- **Gotchas:**
  - First few uploads from a brand-new project may need the channel to be in good standing; brand-new channels can't set custom thumbnails until phone-verified.
  - In Testing mode, refresh tokens expire in 7 days — publish before real users connect.
  - `redirect_uri` mismatch is the #1 OAuth error — it must match byte-for-byte.
  - Honor `5xx` with exponential backoff; `403 quotaExceeded` means stop until reset.
  - Don't poll analytics aggressively; cache and sync on a schedule.

---

## 10. Testing checklist

- [ ] Cloud project created; **YouTube Data API v3** + **YouTube Analytics API** enabled.
- [ ] OAuth consent screen (Google Auth Platform): Branding filled, **External**, test users added, four scopes added in Data Access.
- [ ] Web OAuth client created; redirect URIs match dev + prod exactly; client id/secret in Rails credentials.
- [ ] `bin/rails db:encryption:init` keys present; `SocialAccount.access_token`/`refresh_token` encrypt at rest.
- [ ] Full auth round-trip: consent → callback → tokens stored → `channels.list?mine=true` resolves and stores channel id.
- [ ] Refresh: force-expire `token_expires_at`, confirm `EnsureFreshToken` refreshes and persists.
- [ ] Upload a small **regular** video (resumable, chunked) → `201 Created`, video id stored, appears in Studio (private).
- [ ] Upload a **9:16 ≤3-min** video with `#Shorts` → confirm it lands in the Shorts shelf.
- [ ] `thumbnails.set` on the uploaded video → thumbnail updates (channel must be phone-verified).
- [ ] Simulate an interruption mid-upload → resume via `Content-Range: bytes */TOTAL` → completes.
- [ ] Analytics: `reports.query` for last 30 days returns rows; `channels.list?part=statistics` returns totals.
- [ ] (If used) PubSubHubbub: subscribe → challenge echoed → upload fires a parsed notification; re-subscribe before lease expiry.
- [ ] Revoke app access in the Google account → next call yields `invalid_grant` → `SocialAccount` flips to `needs_reauth`.
- [ ] Quota sanity: confirm an upload consumes ~100 units in the Cloud console **APIs & Services → Quotas**.

---

## API reference quick table

| Operation | HTTP | Scope | Quota | Action class | `SocialAccount` fields touched |
|---|---|---|---|---|---|
| Build consent URL | `GET accounts.google.com/o/oauth2/v2/auth` | — | — | `Actions::AuthorizeUrl` | — |
| Exchange code | `POST oauth2.googleapis.com/token` | — | — | `Actions::ExchangeCode` → `Operations::Youtube::ConnectAccount` | `access_token`, `refresh_token`, `token_expires_at`, `scopes`, `external_channel_id`, `channel_title`, `status` |
| Refresh token | `POST oauth2.googleapis.com/token` | — | — | `Actions::RefreshAccessToken` (via `Operations::Youtube::EnsureFreshToken`) | `access_token`, `token_expires_at`, `status` |
| Upload video / Short | `POST upload/youtube/v3/videos?uploadType=resumable&part=snippet,status` then `PUT` | `youtube.upload` | ~100 | `Actions::UploadVideo` (in `Operations::Youtube::PublishVideo`) | reads `access_token`; writes video id to app model |
| Set thumbnail | `POST upload/youtube/v3/thumbnails/set?videoId=...` | `youtube.upload` | 50 | `Actions::SetThumbnail` | reads `access_token` |
| Channel stats | `GET youtube/v3/channels?part=statistics&mine=true` | `youtube.readonly` | 1 | `Actions::ChannelStats` | reads `access_token`, `external_channel_id` |
| Analytics query | `GET youtubeanalytics.googleapis.com/v2/reports` | `yt-analytics.readonly` | (Analytics quota) | `Actions::QueryAnalytics` | reads `access_token`; updates `last_synced_at` |
| Push subscribe | `POST pubsubhubbub.appspot.com/subscribe` | — | — | `Actions::SubscribePush` | reads `external_channel_id` |
| Webhook callback | `GET/POST /webhooks/youtube` (your app) | — | — | `WebhooksController#youtube` | — |

**Call-site convention:** `Vendors::Youtube::Actions::UploadVideo.call(...)` (always `.call`, never `.new.call`). `Client` holds HTTP/SDK plumbing + base URLs + bearer-token injection; each `Actions::<Verb>` delegates to it. Side effects and token persistence live in `Operations::Youtube::*`. Long uploads run in `Youtube::PublishVideoJob` (Sidekiq).

---

### Primary sources

- Resumable upload protocol — https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol
- `videos.insert` — https://developers.google.com/youtube/v3/docs/videos/insert
- Upload a video — https://developers.google.com/youtube/v3/guides/uploading_a_video
- OAuth (web server) — https://developers.google.com/youtube/v3/guides/auth/server-side-web-apps
- OAuth scopes — https://developers.google.com/identity/protocols/oauth2/scopes#youtube
- `thumbnails.set` — https://developers.google.com/youtube/v3/docs/thumbnails/set
- Analytics `reports.query` — https://developers.google.com/youtube/analytics/reference/reports/query
- Analytics metrics / dimensions — https://developers.google.com/youtube/analytics/metrics , https://developers.google.com/youtube/analytics/dimensions
- `channels.list` — https://developers.google.com/youtube/v3/docs/channels/list
- Quota calculator — https://developers.google.com/youtube/v3/determine_quota_cost
- Revision history (videos.insert cost change 2025-12-04) — https://developers.google.com/youtube/v3/revision_history
- Sensitive-scope verification — https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification
- Unverified apps / verification reqs — https://support.google.com/cloud/answer/7454865 , https://support.google.com/cloud/answer/13464321
- Push notifications (PubSubHubbub) — https://developers.google.com/youtube/v3/guides/push_notifications
- Shorts specs (2025/2026) — https://vidiq.com/blog/post/youtube-shorts-vertical-video/
