# Google Integration Guide — Sign-In · Calendar + Meet · YouTube · Banana (Image Generation)

> Current as of June 2026. One Google Cloud project and one OAuth 2.0 client powers all four
> surfaces: **Sign in with Google** (user auth), **Google Calendar + Meet** (workspace meetings),
> **YouTube Data API v3 + Analytics** (video publishing), and **Google Banana** (Imagen 3 image
> generation via the Google AI API).
>
> Primary refs:
> - https://developers.google.com/youtube/v3/guides/auth/server-side-web-apps
> - https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol
> - https://developers.google.com/calendar/api/guides/overview
> - https://ai.google.dev/api/images (Google AI / Imagen)

---

## 0. What you'll build

| Surface | What it enables |
|---|---|
| **Sign in with Google** | Users authenticate via Google OAuth; `User.google_uid` links the account |
| **Google Calendar + Meet** | `Operations::Meetings::SyncToCalendar` creates/updates Calendar events + Meet links |
| **YouTube** | Upload videos/Shorts, set thumbnails, read channel analytics |
| **Google Banana (Imagen 3)** | Generate images for `feed_image`, `carousel` slides, `story`, `ad`, `thumbnail` types |

All user-facing OAuth (Sign-In, Calendar, YouTube) shares a **single OAuth 2.0 Web client** (one
redirect URI per surface). Google Banana uses a **separate API key** (Google AI Studio key, no user
OAuth needed). Both credentials live in Rails encrypted credentials under the `google:` block.

---

## 1. Prerequisites

1. **A Google account** (ideally a dedicated ops account) to own the Cloud project.
2. **A Google Cloud project** (created in §2) — billing recommended for quota raises.
3. **A Google Workspace or gmail.com account** for the OAuth consent screen branding; if using a
   real domain, verify it in Search Console.
4. **An aistudio.google.com API key** for Banana/Imagen 3 (§6). This is separate from the Cloud
   project OAuth flow.

---

## 2. One GCP project for all Google integrations

> **Console UI note (2024–2025):** "APIs & Services → OAuth consent screen" is now **"Google Auth
> Platform"** with tabs: **Branding**, **Audience**, **Clients**, **Data Access**.
> Clickpath below reflects the current UI.

### 2.1 Create the project

1. Go to `https://console.cloud.google.com/`.
2. Top bar → **project picker** → **New project**.
3. **Name**: `agencios` (or `agencios-prod`). Leave org/location as default. **Create**.
4. Select the new project in the project picker for all subsequent steps.

### 2.2 Enable all APIs in one pass

Navigate to **APIs & Services → Library** and enable:

| API | Purpose | Enable link |
|---|---|---|
| YouTube Data API v3 | Video upload, channel info | `console.cloud.google.com/apis/library/youtube.googleapis.com` |
| YouTube Analytics API | Time-series channel analytics | `console.cloud.google.com/apis/library/youtubeanalytics.googleapis.com` |
| Google Calendar API | Create/update Calendar events | `console.cloud.google.com/apis/library/calendar-json.googleapis.com` |
| Google Meet API (v2) | Attach Meet links to Calendar events | `console.cloud.google.com/apis/library/meet.googleapis.com` |
| People API | Resolve Google user profile on Sign-In | `console.cloud.google.com/apis/library/people.googleapis.com` |

> **Google Banana (Imagen)** is accessed via the Google AI API (`generativelanguage.googleapis.com`)
> using an AI Studio API key, **not** Vertex AI and not this GCP project's OAuth. No library
> enablement needed here for Banana.

### 2.3 Configure the OAuth consent screen (Google Auth Platform)

1. Nav menu → **APIs & Services → OAuth consent screen** (lands on Google Auth Platform).
   Direct: `https://console.cloud.google.com/apis/credentials/consent`
2. **Audience** tab → **External** (unless all users are in your Google Workspace org). This
   starts in **Testing** mode.
3. **Branding** tab → fill: **App name** (`agencios`), **User support email**, **App logo**,
   **Application home page**, **Privacy policy URL**, **Terms of service URL**, **Authorized
   domains** (e.g. `agencios.app`). Must be real and reachable for verification.
4. **Audience** → **Test users** → **Add users**: add every Google email you'll test with while
   in Testing mode (max 100 test users; only they can authorize an unverified app).
5. **Data Access** tab → **Add or remove scopes** → paste all scopes from §3, §4, and §5.3.
   **Update** → **Save**.

### 2.4 Create the OAuth 2.0 Web client

1. **Clients** tab (or **APIs & Services → Credentials**) → **Create credentials → OAuth client ID**.
   Direct: `https://console.cloud.google.com/apis/credentials`
2. **Application type**: **Web application**.
3. **Name**: `agencios-web`.
4. **Authorized redirect URIs** (must match byte-for-byte what Rails sends — no trailing slashes):
   - `https://app.agencios.app/auth/google/callback` — Sign-In
   - `https://app.agencios.app/oauth/youtube/callback` — YouTube
   - `https://app.agencios.app/oauth/calendar/callback` — Calendar (if separate; can share Sign-In)
   - `http://localhost:3000/auth/google/callback` — dev Sign-In
   - `http://localhost:3000/oauth/youtube/callback` — dev YouTube
   - `http://localhost:3000/oauth/calendar/callback` — dev Calendar
5. **Create** → copy **Client ID** (`...apps.googleusercontent.com`) + **Client secret** (GOCSPX-...).

---

## 3. Google Sign-In (user authentication)

### 3.1 Scopes

| Scope | Why |
|---|---|
| `openid` | Standard OIDC identity |
| `email` | User's primary email |
| `profile` | `name`, `picture`, `given_name` |
| `https://www.googleapis.com/auth/calendar` | Read/write Calendar events (**only when user also connects Calendar**) |

For plain Sign-In, request only `openid email profile`. Calendar scope is added when the user
explicitly connects Calendar (incremental auth via `include_granted_scopes=true`).

### 3.2 OAuth flow (omniauth-google-oauth2)

agencios uses the `omniauth-google-oauth2` gem. The callback is `GET /auth/google/callback`.

**Redirect to consent:**
```
GET https://accounts.google.com/o/oauth2/v2/auth
  ?client_id={CLIENT_ID}
  &redirect_uri=https://app.agencios.app/auth/google/callback
  &response_type=code
  &scope=openid email profile
  &access_type=online          # online for Sign-In (no offline refresh needed)
  &state={CSRF_TOKEN}
```

For Calendar connection (offline access + refresh token):
```
  &scope=openid email profile https://www.googleapis.com/auth/calendar
  &access_type=offline
  &prompt=consent              # forces a refresh token to be issued
  &include_granted_scopes=true
```

**Exchange code → tokens** at `POST https://oauth2.googleapis.com/token`.
→ `Vendors::Google::Actions::ExchangeCode`

**After Sign-In:** upsert `User` by `google_uid`. If Calendar scopes were granted, also persist the
refresh token (§4.3).

### 3.3 User model columns (Google Sign-In)

```ruby
# In the users migration / existing schema
t.string   :google_uid                           # unique; links the Google account
t.text     :google_access_token                  # encrypted; for Calendar calls if connected
t.text     :google_refresh_token                 # encrypted; for Calendar token refresh
t.datetime :google_calendar_connected_at         # nil if Calendar not connected
```

```ruby
class User < ApplicationRecord
  encrypts :google_access_token
  encrypts :google_refresh_token

  def google_connected? = google_uid.present?
  def google_calendar_connected? = google_calendar_connected_at.present?
end
```

---

## 4. Google Calendar + Meet

### 4.1 Scopes

| Scope | Why |
|---|---|
| `https://www.googleapis.com/auth/calendar` | Full read/write on the user's Calendar |
| `https://www.googleapis.com/auth/calendar.events` | Narrower: only create/edit/delete events (prefer this) |

Use `calendar.events` — it has narrower blast radius. Request it during the initial Sign-In
(`access_type=offline`, `prompt=consent`) or as an incremental grant from Settings.

### 4.2 Calendar API — operations

Gems: `google-apis-calendar_v3` + `google-apis-meet_v2`.

**Create a Calendar event with a Meet link:**
```ruby
service = Google::Apis::CalendarV3::CalendarService.new
service.authorization = Signet::OAuth2::Client.new(
  access_token: user.google_access_token
)

event = Google::Apis::CalendarV3::Event.new(
  summary: meeting.title,
  description: meeting.notes,
  start: { date_time: meeting.starts_at.iso8601, time_zone: workspace.timezone },
  finish: { date_time: meeting.ends_at.iso8601, time_zone: workspace.timezone },
  attendees: meeting.attendees.map { |a| { email: a["email"] } },
  conference_data: { create_request: { request_id: SecureRandom.hex(8) } }
)

result = service.insert_event("primary", event, conference_data_version: 1)
# result.id             → google_event_id
# result.hangout_link   → meet_url (e.g. https://meet.google.com/xxx-xxxx-xxx)
```

**Update:**
```ruby
service.update_event("primary", meeting.google_event_id, event, conference_data_version: 1)
```

**Delete:**
```ruby
service.delete_event("primary", meeting.google_event_id)
```

→ `Vendors::Google::Calendar::Actions::CreateEvent` + `UpdateEvent` + `DeleteEvent`

### 4.3 Token storage

Calendar tokens are stored **on the `User`** (not `SocialAccount`) because Calendar is a personal
connection tied to a specific Google account.

```ruby
# Operations::Meetings::EnsureFreshCalendarToken
# Refreshes if expiring within 60 seconds; persists new token.
response = Vendors::Google::Actions::RefreshAccessToken.call(
  refresh_token: user.google_refresh_token
)
user.update!(
  google_access_token: response.access_token,
  google_calendar_connected_at: Time.current
)
```

### 4.4 Wiring in agencios

```
Operations::Meetings::SyncToCalendar.call(meeting:)
  → Operations::Meetings::EnsureFreshCalendarToken.call(user: meeting.workspace.owner)
  → Vendors::Google::Calendar::Actions::CreateEvent.call(...)
  → meeting.update!(google_event_id:, meet_url:)

Operations::Meetings::RemoveFromCalendar.call(meeting:)
  → Vendors::Google::Calendar::Actions::DeleteEvent.call(...)
```

`SyncToCalendar` is called explicitly from the service layer when a meeting is created or updated.
**No AR callbacks.** `Meeting` records store `google_event_id` and `meet_url` for display on the
calendar view (`/calendario`).

### 4.5 Setting (workspace-level Calendar connection)

The `Setting` model stores workspace-level Google tokens when the agency connects a shared
workspace calendar (optional, in addition to per-user Calendar):

```ruby
# Setting model — workspace-level tokens (encrypted)
encrypts :google_access_token
encrypts :google_refresh_token
```

If both a workspace token and a user token exist, prefer the workspace token for event creation.

---

## 5. YouTube (video publishing + analytics)

YouTube shares the same OAuth client and `google:` credential block as Sign-In and Calendar.
The `SocialAccount` model stores the per-workspace YouTube channel connection.

### 5.1 Scopes

| Scope | Why | Sensitivity |
|---|---|---|
| `https://www.googleapis.com/auth/youtube.upload` | `videos.insert`, `thumbnails.set` | **Sensitive** |
| `https://www.googleapis.com/auth/youtube.readonly` | `channels.list`, `videos.list` | **Sensitive** |
| `https://www.googleapis.com/auth/yt-analytics.readonly` | Analytics API `reports.query` | **Sensitive** |

> All YouTube scopes are **Sensitive** (not Restricted). Sensitive-scope verification requires
> brand verification + scope justification + a **demo video** (unlisted, on YouTube) showing the
> consent flow and actual scope usage.
>
> **Testing mode:** refresh tokens expire after **7 days**. Publish the app to fix for real users.

### 5.2 OAuth flow (authorization-code, offline)

```
GET https://accounts.google.com/o/oauth2/v2/auth
  ?client_id={CLIENT_ID}
  &redirect_uri=https://app.agencios.app/oauth/youtube/callback
  &response_type=code
  &scope=https://www.googleapis.com/auth/youtube.upload
         https://www.googleapis.com/auth/youtube.readonly
         https://www.googleapis.com/auth/yt-analytics.readonly
  &access_type=offline
  &prompt=consent            # forces refresh_token to be returned
  &include_granted_scopes=true
  &state={CSRF_TOKEN}
```

Exchange code → `{ access_token, refresh_token, expires_in }` at
`POST https://oauth2.googleapis.com/token`.

Immediately call `channels.list?part=id,snippet&mine=true` to resolve and store the channel id.
→ `Operations::Youtube::ConnectAccount`

**Token refresh (access tokens ~1 hour):**
```
POST https://oauth2.googleapis.com/token
  client_id={CLIENT_ID} &client_secret={CLIENT_SECRET}
  &refresh_token={STORED_REFRESH_TOKEN} &grant_type=refresh_token
→ { access_token, expires_in }
```
Handle `invalid_grant` → mark `SocialAccount` `needs_reauth`.
→ `Operations::Youtube::EnsureFreshToken`

### 5.3 `SocialAccount` columns for YouTube

```ruby
t.string   :external_channel_id        # YouTube channel id (UC...)
t.string   :channel_title
t.text     :access_token               # encrypted
t.text     :refresh_token              # encrypted
t.datetime :token_expires_at
t.string   :scopes
t.string   :status, default: "connected"   # connected | needs_reauth | revoked
t.datetime :last_synced_at

add_index :social_accounts, [:workspace_id, :provider, :external_channel_id], unique: true
```

### 5.4 Video upload — resumable protocol

References: https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol

**Step 1 — Initiate session:**
```
POST https://www.googleapis.com/upload/youtube/v3/videos
  ?uploadType=resumable&part=snippet,status
  Authorization: Bearer {ACCESS_TOKEN}
  Content-Type: application/json; charset=UTF-8
  X-Upload-Content-Length: {TOTAL_BYTES}
  X-Upload-Content-Type: video/*

{
  "snippet": {
    "title": "...",
    "description": "...",
    "tags": [...],
    "categoryId": "22",
    "defaultLanguage": "pt-BR"
  },
  "status": {
    "privacyStatus": "public",          # or "private" (+ publishAt for scheduled)
    "selfDeclaredMadeForKids": false,   # REQUIRED — COPPA flag
    "embeddable": true,
    "containsSyntheticMedia": false     # set true for AI-generated content
  }
}
→ HTTP 200 with Location: <SESSION_URI>
```

**Step 2 — Upload bytes** (chunked, each chunk a multiple of 262144 bytes):
```
PUT {SESSION_URI}
  Authorization: Bearer {ACCESS_TOKEN}
  Content-Range: bytes 0-262143/TOTAL
  <chunk bytes>
→ 308 Resume Incomplete (intermediate) | 201 Created (final, returns video resource with id)
```

**Resume on failure:**
```
PUT {SESSION_URI}
  Authorization: Bearer {ACCESS_TOKEN}
  Content-Length: 0
  Content-Range: bytes */TOTAL
→ 308 with Range: bytes=0-N → resume from byte N+1
→ 404 → session expired, restart from Step 1
```
→ `Vendors::Youtube::Actions::UploadVideo`

**Shorts** — no separate API field. Upload a vertical 9:16, ≤3 min video with `#Shorts` in the
title or description. YouTube auto-classifies it as a Short.

**Custom thumbnail:**
```
POST https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId={VIDEO_ID}
  Authorization: Bearer {ACCESS_TOKEN}
  Content-Type: image/jpeg
  <image bytes ≤ 2 MB, recommended 1280×720>
```
→ `Vendors::Youtube::Actions::SetThumbnail` (50 quota units; requires phone-verified channel)

### 5.5 Publishing operation

```ruby
# app/services/operations/youtube/publish_video.rb
module Operations
  module Youtube
    class PublishVideo < Operations::Base
      def call(social_account:, file:, metadata:, thumbnail: nil)
        Operations::Youtube::EnsureFreshToken.call(social_account:)
        video_id = Vendors::Youtube::Actions::UploadVideo.call(
          social_account:, file_path: file, metadata:
        )
        Vendors::Youtube::Actions::SetThumbnail.call(
          social_account:, video_id:, image_path: thumbnail
        ) if thumbnail
        video_id
      end
    end
  end
end
```

Run from `Youtube::PublishVideoJob` (Sidekiq, `media` queue — uploads are slow).

### 5.6 Analytics

**Time-series via YouTube Analytics API:**
```
GET https://youtubeanalytics.googleapis.com/v2/reports
  ?ids=channel==MINE
  &startDate=2026-01-01&endDate=2026-06-30
  &metrics=views,estimatedMinutesWatched,likes,comments,subscribersGained
  &dimensions=day
  &sort=day
  Authorization: Bearer {ACCESS_TOKEN}
```
Common metrics: `views`, `estimatedMinutesWatched`, `averageViewDuration`, `averageViewPercentage`,
`likes`, `dislikes`, `comments`, `shares`, `subscribersGained`, `subscribersLost`.
→ `Vendors::Youtube::Actions::QueryAnalytics`

**Lifetime channel stats:**
```
GET https://www.googleapis.com/youtube/v3/channels?part=statistics&mine=true
  Authorization: Bearer {ACCESS_TOKEN}
→ { statistics: { viewCount, subscriberCount, hiddenSubscriberCount, videoCount } }
```
→ `Vendors::Youtube::Actions::ChannelStats` (1 quota unit)

**Quota:** 10,000 units/day (default, per project). `videos.insert` ≈ **100 units** (reduced from
~1600 on 2025-12-04). `thumbnails.set` = 50 units. `search.list` = 100 units (avoid for lookups).
`channels.list`/`videos.list` = 1 unit. No self-service quota increase — submit the audit form.

### 5.7 PubSubHubbub push notifications

For reacting to uploads on a channel (e.g. confirming a Short went live):

```
POST https://pubsubhubbub.appspot.com/subscribe
  hub.callback=https://app.agencios.app/webhooks/youtube
  hub.topic=https://www.youtube.com/xml/feeds/videos.xml?channel_id={CHANNEL_ID}
  hub.mode=subscribe
  hub.verify=async
```
Verification: hub GETs your callback with `hub.challenge` — echo it back (200). Notifications are
POSTed as Atom XML with `<yt:videoId>`. Leases ~5–10 days — re-subscribe via Sidekiq cron.
→ `Vendors::Youtube::Actions::SubscribePush` + `WebhooksController#youtube`

---

## 6. Google Banana — image generation (Imagen 3)

**Google Banana** is agencios's image generation vendor, backed by **Google's Imagen 3** model
via the [Google AI API](https://ai.google.dev/api/images). It generates images for
`feed_image`, `carousel` slides, `story`, `ad`, and `thumbnail` creative types.

This is a **pure API-key integration** — no user OAuth, no GCP project OAuth client. The API key
is issued from [Google AI Studio](https://aistudio.google.com/apikey).

### 6.1 Credentials

```yaml
# In Rails encrypted credentials (separate from the google: OAuth block)
google_banana:
  api_key:   "AIza..."          # Google AI Studio API key
  model:     "imagen-3.0-generate-002"   # current Imagen 3 model
```

ENV fallbacks: `GOOGLE_BANANA_API_KEY` / `GOOGLE_BANANA_MODEL`.

> **Why a separate block?** The `google:` block holds OAuth client credentials (user-facing flows).
> Banana uses a server-side API key with completely different auth — keeping them separate avoids
> confusion and scoping leaks.

### 6.2 Generate an image

```
POST https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:predict
  ?key={API_KEY}
  Content-Type: application/json

{
  "instances": [
    { "prompt": "A vibrant product photo for a Brazilian skincare brand, white background, studio lighting" }
  ],
  "parameters": {
    "sampleCount": 1,
    "aspectRatio": "1:1",           # "1:1" | "16:9" | "9:16" | "4:3" | "3:4"
    "outputMimeType": "image/jpeg", # "image/jpeg" | "image/png"
    "negativePrompt": "blur, text, watermark, low quality",
    "personGeneration": "allow_adult",   # "dont_allow" | "allow_adult" | "allow_all"
    "safetySetting": "block_some"   # "block_most" | "block_some" | "block_few"
  }
}
```

**Response:**
```json
{
  "predictions": [
    {
      "bytesBase64Encoded": "<base64-encoded image bytes>",
      "mimeType": "image/jpeg"
    }
  ]
}
```

Decode `bytesBase64Encoded` → raw bytes → store to ActiveStorage.

**Aspect ratios for each creative type:**

| Creative type | Aspect ratio | Notes |
|---|---|---|
| `feed_image` | `1:1` | Square Instagram/Facebook feed |
| `carousel` slide | `1:1` or `4:3` | 1080×1080 or 1080×810 |
| `story` | `9:16` | 1080×1920 |
| `ad` | `1:1` or `16:9` | Depends on placement |
| `thumbnail` | `16:9` | 1280×720 (YouTube) |
| `cover` | `16:9` | Social cover / profile banner |

### 6.3 Vendor wiring

```
app/services/vendors/google/banana/
  client.rb                     # HTTP wrapper — sets key in URL, parses response
  actions/
    generate_image.rb           # single call: prompt + params → raw image bytes
    generate_batch.rb           # sampleCount > 1 → multiple images in one call (up to 4)
```

```ruby
# Vendors::Google::Banana::Actions::GenerateImage
module Vendors
  module Google
    module Banana
      module Actions
        class GenerateImage < ::Vendors::Base
          def call(prompt:, aspect_ratio: "1:1", negative_prompt: nil, sample_count: 1)
            Vendors::Google::Banana::Client.new.generate(
              prompt:, aspect_ratio:, negative_prompt:, sample_count:
            )
          end
        end
      end
    end
  end
end
```

**Call site:**
```ruby
Vendors::Google::Banana::Actions::GenerateImage.call(
  prompt: "...",
  aspect_ratio: "1:1"
)
```

### 6.4 Integration into the creative generation pipeline

`Operations::Creatives::GenerateImage` calls Banana for `feed_image`, `story`, `ad`, `thumbnail`,
and `cover` creative types. `Operations::Creatives::GenerateCarousel` uses Banana to render each
individual slide image (after copy is assembled by `Prompts::CarouselCopy`).

```ruby
# Operations::Creatives::GenerateImage (sketch)
module Operations
  module Creatives
    class GenerateImage < Operations::Base
      def call(ticket:, prompt:, ref_images: [], creative_type: "feed_image")
        spec   = Creatives.for(creative_type).spec
        aspect = spec[:aspect_ratio]

        creative = Operations::Creatives::Create.call(
          ticket:, source: :generated, creative_type:, status: :generating
        )
        generation = Generation.create!(
          workspace: ticket.workspace, user: Current.user,
          creative:, kind: :image, status: :queued,
          provider: "google_banana", params: { prompt:, aspect_ratio: aspect }
        )

        bytes = Vendors::Google::Banana::Actions::GenerateImage.call(
          prompt: build_prompt(prompt, spec),
          aspect_ratio: aspect
        )

        creative.assets.attach(
          io: StringIO.new(bytes),
          filename: "creative-#{creative.id}.jpg",
          content_type: "image/jpeg"
        )
        creative.update!(status: :ready)
        generation.update!(status: :completed, cost_cents: 0)

        ActionCable.server.broadcast("generations_#{ticket.workspace_id}", {
          event: "creative_ready", creative_id: creative.id
        })

        creative
      end
    end
  end
end
```

> **Billing note:** image generations are tracked (`Generation(kind: image)`) but currently **not
> metered** via Stripe. Only `carousel` and `video` generations emit Stripe meter events. Revisit
> if Banana costs warrant a third meter (`image_generation`).

### 6.5 Prompts for Banana

`Prompts::CarouselCopy`, `Prompts::IdeaSynthesis`, etc. build the _copy_ (Claude). The actual
**image prompt** for Banana is built by a dedicated helper in the creative type's `.spec` — the
`generation_prompt_scaffold` field is a template (workspace brand voice + colors + content type +
safe areas). `Operations::Creatives::GenerateImage` merges ticket context into the scaffold before
calling Banana.

---

## 7. Credentials summary

```yaml
# Rails encrypted credentials — all Google surfaces

google:
  client_id:     "xxxx.apps.googleusercontent.com"   # OAuth client — Sign-In, Calendar, YouTube
  client_secret: "GOCSPX-xxxx"                        # OAuth client secret

google_banana:
  api_key:   "AIza..."                        # Google AI Studio key — Imagen 3 image generation
  model:     "imagen-3.0-generate-002"        # current model version
```

**ENV fallbacks (dev `.env` only; never in production):**

| Credential | ENV |
|---|---|
| `google.client_id` | `GOOGLE_CLIENT_ID` |
| `google.client_secret` | `GOOGLE_CLIENT_SECRET` |
| `google_banana.api_key` | `GOOGLE_BANANA_API_KEY` |
| `google_banana.model` | `GOOGLE_BANANA_MODEL` |

**Redirect URIs to register** on the OAuth client (§2.4):

| Surface | Path | Notes |
|---|---|---|
| Sign-In | `/auth/google/callback` | omniauth-google-oauth2 |
| Calendar (incremental) | `/auth/google/callback` | same URI, additional scopes |
| YouTube | `/oauth/youtube/callback` | dedicated flow |

---

## 8. Testing checklist

### GCP / OAuth setup
- [ ] Cloud project created; all five APIs enabled (YouTube Data, YouTube Analytics, Calendar,
      Meet, People).
- [ ] OAuth consent screen: Branding filled, External audience, test users added, all scopes in
      Data Access.
- [ ] Web OAuth client created; all redirect URIs registered (dev + prod); client id/secret in
      Rails credentials.
- [ ] `bin/rails db:encryption:init` keys present; encrypted columns work.

### Sign-In
- [ ] OAuth round-trip: consent → callback → `User` upserted (or linked) via `google_uid`.
- [ ] Signing in with an existing email/password account links the Google UID.

### Calendar + Meet
- [ ] Calendar scopes granted (incremental, from Settings); refresh token stored on User.
- [ ] Creating a Meeting → `SyncToCalendar` → Calendar event created with Meet link; `google_event_id`
      and `meet_url` stored; event visible in Google Calendar.
- [ ] Updating a Meeting → `SyncToCalendar` → event updated.
- [ ] Deleting a Meeting → `RemoveFromCalendar` → event deleted.
- [ ] `EnsureFreshCalendarToken` refreshes before expiry; `invalid_grant` marks the connection broken.

### YouTube
- [ ] YouTube OAuth round-trip: consent → tokens stored → `channels.list?mine=true` resolves and
      stores channel id.
- [ ] `EnsureFreshToken` refreshes; `invalid_grant` → `needs_reauth`.
- [ ] Upload a small **regular** video (resumable) → `201 Created`, video id stored.
- [ ] Upload a **9:16 ≤3-min** video with `#Shorts` → lands in Shorts shelf.
- [ ] `thumbnails.set` updates the thumbnail (phone-verified channel).
- [ ] Interrupted upload resumed via `Content-Range: bytes */TOTAL`.
- [ ] Analytics `reports.query` returns rows; `channels.list?part=statistics` returns totals.
- [ ] PubSubHubbub: subscribe → challenge echoed → upload fires notification → re-subscribe before
      lease expiry.
- [ ] Quota: upload consumes ~100 units in Cloud Console.
- [ ] Publish + verify: `Audience → Publish app` → verification center → submit sensitive scopes
      with screencasts.

### Google Banana (image generation)
- [ ] API key in Rails credentials; `GOOGLE_BANANA_API_KEY` ENV fallback works in dev.
- [ ] `Vendors::Google::Banana::Actions::GenerateImage.call(prompt: "...", aspect_ratio: "1:1")`
      returns image bytes.
- [ ] `Operations::Creatives::GenerateImage` creates `Creative(status: ready)` + `Generation(kind: image,
      status: completed)` and attaches the asset to ActiveStorage.
- [ ] `Operations::Creatives::GenerateCarousel` generates each slide via Banana and assembles the
      carousel with brand overlays.
- [ ] `ActionCable` broadcasts `creative_ready` after generation completes.
- [ ] Unsupported aspect ratio or safety-blocked prompt returns a graceful failure → `Creative(status: failed)`.

---

## 9. Rate limits & gotchas

- **YouTube quota:** 10,000 units/day (default, per project). `videos.insert` ≈ 100 units.
  `search.list` = 100 units — avoid for id lookups; use `channels.list`/`videos.list` (1 unit).
  Honor `5xx` with exponential backoff; `403 quotaExceeded` → stop until midnight Pacific reset.
- **YouTube Analytics quota:** separate from Data API; not unit-priced the same way — don't sync
  aggressively; cache and poll on a schedule.
- **YouTube Shorts:** no API field — classify by media (9:16, ≤3 min) + `#Shorts` in title/desc.
- **Refresh token expiry:** Testing mode = 7 days. Production = revoked if unused ~6 months or >50
  live tokens per (user, client). Handle `invalid_grant`.
- **Calendar token scope:** Calendar tokens live on the **User** (personal calendar), not on the
  workspace-level `SocialAccount`. `Setting` holds an optional shared workspace calendar token.
- **Google Banana — no streaming:** the Imagen API returns the full image in one response (no
  streaming). Timeouts are typically 10–30s for a single image; run generation in Sidekiq.
- **Google Banana — safety filters:** `BLOCK_ERROR` (safety-blocked prompt) → retry with a revised
  prompt or surface an error; don't expose the raw API error to the user.
- **Google Banana — pricing:** Imagen 3 is billed per image generated. Track `cost_cents` on
  `Generation` (convert from the Google AI pricing sheet). Currently not metered via Stripe.
- **`redirect_uri` mismatch** is the #1 OAuth error across all Google flows — must be byte-for-byte
  exact (scheme, host, path, no trailing slash).
- **Sensitive-scope verification** (YouTube) requires a demo video + scope justifications. Brand
  verification first (~2–3 days), then full review (days–weeks). Plan launch around it.

---

## API reference quick tables

### Sign-In & token management

| Operation | HTTP | Action class | Notes |
|---|---|---|---|
| Build consent URL | `GET accounts.google.com/o/oauth2/v2/auth` | `Vendors::Google::Actions::AuthorizeUrl` | scope includes Calendar for incremental |
| Exchange code | `POST oauth2.googleapis.com/token` | `Vendors::Google::Actions::ExchangeCode` | → `Operations::Users::ConnectGoogle` |
| Refresh access token | `POST oauth2.googleapis.com/token` | `Vendors::Google::Actions::RefreshAccessToken` | used by Calendar + YouTube EnsureFreshToken |

### Calendar + Meet

| Operation | Gem method | Action class | SocialAccount / User field |
|---|---|---|---|
| Create event + Meet | `service.insert_event` (`conference_data_version: 1`) | `Vendors::Google::Calendar::Actions::CreateEvent` | reads `user.google_access_token` |
| Update event | `service.update_event` | `Vendors::Google::Calendar::Actions::UpdateEvent` | reads `user.google_access_token` |
| Delete event | `service.delete_event` | `Vendors::Google::Calendar::Actions::DeleteEvent` | reads `user.google_access_token` |

### YouTube

| Operation | HTTP | Scope | Quota | Action class | SocialAccount fields |
|---|---|---|---|---|---|
| Build consent URL | `GET accounts.google.com/o/oauth2/v2/auth` | — | — | `Actions::AuthorizeUrl` | — |
| Exchange code | `POST oauth2.googleapis.com/token` | — | — | `Actions::ExchangeCode` → `Operations::Youtube::ConnectAccount` | writes all token fields |
| Refresh token | `POST oauth2.googleapis.com/token` | — | — | `Actions::RefreshAccessToken` (via `EnsureFreshToken`) | `access_token`, `token_expires_at` |
| Upload video | `POST upload/youtube/v3/videos?uploadType=resumable` then `PUT {session_uri}` | `youtube.upload` | ~100 | `Actions::UploadVideo` | reads `access_token` |
| Set thumbnail | `POST upload/youtube/v3/thumbnails/set?videoId=...` | `youtube.upload` | 50 | `Actions::SetThumbnail` | reads `access_token` |
| Channel stats | `GET youtube/v3/channels?part=statistics&mine=true` | `youtube.readonly` | 1 | `Actions::ChannelStats` | reads `access_token` |
| Analytics query | `GET youtubeanalytics.googleapis.com/v2/reports` | `yt-analytics.readonly` | (Analytics quota) | `Actions::QueryAnalytics` | reads `access_token` |
| Push subscribe | `POST pubsubhubbub.appspot.com/subscribe` | — | — | `Actions::SubscribePush` | reads `external_channel_id` |

### Google Banana (Imagen 3)

| Operation | HTTP | Action class | Credential |
|---|---|---|---|
| Generate image | `POST generativelanguage.googleapis.com/v1beta/models/{model}:predict?key={API_KEY}` | `Vendors::Google::Banana::Actions::GenerateImage` | `google_banana.api_key` |
| Generate batch (up to 4) | same endpoint with `sampleCount: 2-4` | `Vendors::Google::Banana::Actions::GenerateBatch` | `google_banana.api_key` |
