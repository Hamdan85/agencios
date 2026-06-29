# HeyGen API — UGC / Avatar Talking-Head Video Generation (agencios)

> Research current as of 2025–2026. The HeyGen docs have migrated: `docs.heygen.com/*`
> now shows a v1/v2→v3 migration banner. The authoritative live docs are at
> **`developers.heygen.com`** (Mintlify; append `.md` to any page for clean markdown).
> Two API generations coexist: the classic **v2** (`POST /v2/video/generate`,
> `video_inputs`) is supported **through Oct 31, 2026**; the new **v3** (`POST /v3/videos`)
> is where new development is focused. URL map: https://developers.heygen.com/llms.txt

## 0. What you'll build (UGC video generation inside agencios)

A server-side pipeline that turns a **script + chosen avatar + chosen voice** into a
rendered talking-head MP4, fully programmatically — no human in HeyGen's web Studio.

The flow is async and four-stepped:

1. **Pick assets** — list HeyGen avatars (`GET /v2/avatars`) and voices (`GET /v2/voices`)
   once, cache them, and let the agency operator (or an automated brief) choose an
   `avatar_id` + `voice_id`. (https://developers.heygen.com/more-legacy-api.md)
2. **Submit a generation job** — `POST /v2/video/generate` (or `POST /v3/videos`) with the
   script as `input_text`/`script`. HeyGen returns a `video_id` immediately; rendering is
   asynchronous. (https://developers.heygen.com/reference/create-video.md)
3. **Get notified** — register a webhook so HeyGen calls you back with
   `avatar_video.success` (carrying the final `video_url`) or `avatar_video.fail`. Polling
   `GET /v1/video_status.get` is the fallback. (https://developers.heygen.com/docs/webhook-events.md)
4. **Store + serve** — download the MP4 (HeyGen URLs are presigned and expire), attach it to
   a `Creative` record, and surface it in the agency dashboard.
   (https://developers.heygen.com/reference/get-video.md)

For repeatable branded UGC ad formats, also use **Templates**: design an ad layout once in
HeyGen Studio (avatar placement, captions, B-roll, brand frame), expose `{{script}}` /
`{{product_image}}` as variables, and fire `POST /v2/template/{template_id}/generate` with
`variables` per ad. (https://developers.heygen.com/template-api.md)

For "creator-from-a-photo" UGC (your own UGC actor headshot reading a script), use **Photo
Avatar / Avatar IV**. (https://developers.heygen.com/photo-avatar.md,
https://developers.heygen.com/avatar-iv.md)

## 1. Get API key (clickpath in HeyGen dashboard)

- **Clickpath:** HeyGen dashboard → the **API** section → **"Click to generate your API
  key."** Direct link `https://app.heygen.com/home?from=&nav=API`. In the UI this is reached
  via **Settings → API** (also surfaced as Space Settings → API).
  (https://developers.heygen.com/docs/api-key.md)
- **Header:** Every request authenticates via the **`X-Api-Key`** header. Base URL for all
  endpoints is **`https://api.heygen.com`**. (https://developers.heygen.com/docs/api-key.md)
- **Verify the key works:** call `GET /v3/users/me` (a `GET /v1/user/me` variant is shown in
  the curl example). The same `me` call returns your prepaid **`wallet`** balance.
  (https://developers.heygen.com/docs/api-key.md, https://developers.heygen.com/docs/pricing.md)
- **Free vs paid:** Billing is **pay-as-you-go from a prepaid USD wallet** — buy the exact
  amount of API credits you like, no plan/subscription required; **any user (including free
  account holders) can buy credits** independently of the consumer subscription plans. Docs
  do NOT explicitly state a brand-new free account can mint a working key with a zero
  balance — assume "key generation likely allowed, but real renders require a funded wallet."
  (https://developers.heygen.com/docs/pricing.md,
  https://help.heygen.com/en/articles/10060327-heygen-api-pricing-explained)

```bash
curl https://api.heygen.com/v1/user/me \
  -H "X-Api-Key: $HEYGEN_API_KEY"
```

Security rules from the docs: never commit the key, never expose it in browser/client code,
always call from a backend. (https://developers.heygen.com/docs/api-key.md)

## 2. Core concepts (avatars, voices, templates, credits)

- **Avatar** — a presenter you drive with text. Identified by `avatar_id`. Three v2 render
  styles: **`normal`**, **`closeUp`**, **`circle`**. Two character `type`s: **`avatar`** (a
  HeyGen studio avatar) and **`talking_photo`** (a Photo Avatar).
  (https://developers.heygen.com/more-legacy-api.md)
- **Voice** — TTS voice identified by `voice_id`. You pass `input_text` (the script) and
  HeyGen lip-syncs the avatar. Voices vary in language, gender, and capabilities
  (pause/emotion). (https://developers.heygen.com/more-legacy-api.md)
- **Template** — a pre-built Studio scene with named **variables** (text/image/video/
  audio/voice/character). Design the branded ad once, then fill variables per generation.
  Best fit for consistent UGC ad formats at scale. (https://developers.heygen.com/template-api.md)
- **Photo Avatar / Avatar IV** — generate a talking avatar from a single photo. **Avatar
  IV** is the default v3 engine and adds `motion_prompt` (natural-language gesture control)
  and `expressiveness` (`high`/`medium`/`low`).
  (https://developers.heygen.com/avatar-iv.md, https://developers.heygen.com/photo-avatar.md)
- **Credits / wallet** — usage is deducted from a **prepaid USD wallet**; pricing is per
  second of output (see §6). Rule of thumb: **$1 ≈ 1 minute** of standard 720p/1080p avatar
  video. (https://developers.heygen.com/docs/pricing.md,
  https://help.heygen.com/en/articles/10060327-heygen-api-pricing-explained)
- **Async by design** — generate returns a `video_id`; the rendered file arrives via webhook
  or status poll. Status values: **`pending` / `waiting` / `processing` / `completed` /
  `failed`**. (https://developers.heygen.com/reference/get-video.md,
  https://apidog.com/blog/heygen-api/)
- **`test` mode** — v2 supports a `test` flag that renders a lower-quality preview and **does
  not deduct quota** — invaluable for development.
  (https://developers.heygen.com/more-legacy-api.md)

## 3. Generate a video — endpoints + JSON payloads

### 3a. v2 — `POST https://api.heygen.com/v2/video/generate` (supported through Oct 31 2026)

Top-level fields: **`video_inputs`** (array of 1–50 scenes, required), **`dimension`**
(`{width,height}`, default 1920×1080), **`caption`** (bool), **`title`**, **`callback_id`**,
**`callback_url`**, **`fps`** (default 25.0), **`test`** (bool).
(https://developers.heygen.com/more-legacy-api.md)

Each `video_inputs[]` scene has three sub-objects:
- **`character`** — `type` ("avatar" | "talking_photo"); for avatar: `avatar_id` (required),
  `avatar_style` ("normal" | "closeUp" | "circle"), plus `scale`, `offset`, `fit`. Avatar IV
  via `use_avatar_iv_model` (e.g. model `"4.3_turbo"`).
- **`voice`** — `type` ("text" | "audio" | "silence"); for text: `voice_id`, `input_text`,
  `speed` (0.5–1.5), `pitch`, `emotion`. For audio: `audio_url` or `audio_asset_id`.
- **`background`** — `type` ("color" | "image" | "video"); `value` (hex color), or
  `url`/asset IDs for media; `fit` ("cover" | "contain" | "crop" | "none").

(All field detail: https://developers.heygen.com/more-legacy-api.md)

**Example request** (https://apidog.com/blog/heygen-api/,
https://developers.heygen.com/more-legacy-api.md):

```json
POST https://api.heygen.com/v2/video/generate
X-Api-Key: <key>
Content-Type: application/json

{
  "title": "UGC ad - SummerSale - variant A",
  "caption": false,
  "dimension": { "width": 1080, "height": 1920 },
  "callback_id": "creative_8842",
  "test": false,
  "video_inputs": [
    {
      "character": {
        "type": "avatar",
        "avatar_id": "Angela-inTshirt-20220820",
        "avatar_style": "normal"
      },
      "voice": {
        "type": "text",
        "input_text": "Stop scrolling — this is the product that changed my routine.",
        "voice_id": "1bd001e7e50f421d891986aad5158bc8",
        "speed": 1.1
      },
      "background": { "type": "color", "value": "#87CEEB" }
    }
  ]
}
```

**Example response** (https://developers.heygen.com/more-legacy-api.md):

```json
{ "error": null, "data": { "video_id": "af273759c9xa47369e05418c69drq174" } }
```

`input_text` must be **under 5000 characters** per scene.
(https://developers.heygen.com/more-legacy-api.md)

### 3b. v3 — `POST https://api.heygen.com/v3/videos` (recommended for new builds)

v3 flattens the schema into a **discriminated union on `type`** (`"avatar"` | `"image"` |
`"cinematic_avatar"`), replaces `dimension` with `aspect_ratio` + `resolution`, and uses
`script` instead of `voice.input_text`. (https://developers.heygen.com/reference/create-video.md)

```json
POST https://api.heygen.com/v3/videos
{
  "type": "avatar",
  "avatar_id": "Angela-inTshirt-20220820",
  "script": "Stop scrolling — this is the product that changed my routine.",
  "voice_id": "1bd001e7e50f421d891986aad5158bc8",
  "title": "UGC ad - SummerSale - variant A",
  "aspect_ratio": "9:16",
  "resolution": "1080p",
  "background": { "type": "color", "value": "#87CEEB" },
  "caption": { "file_format": "srt", "style": "default" },
  "callback_url": "https://agencios.app/webhooks/heygen",
  "callback_id": "creative_8842"
}
```

Response: `{ "data": { "video_id": "v_abc123def456", "status": "waiting",
"output_format": "mp4" } }`. Error shape: `{ "error": { "code": "invalid_parameter",
"message": "...", "param": "avatar_id", "doc_url": null } }`.
(https://developers.heygen.com/reference/create-video.md)

Key v3 fields: `aspect_ratio` ("16:9","9:16","4:5","5:4","1:1","auto"), `resolution`
("4k","1080p","720p"), `output_format` ("mp4"/"webm"), `engine`
(`avatar_iii`/`avatar_iv`/`avatar_v` — defaults to Avatar IV).
(https://developers.heygen.com/reference/create-video.md, https://developers.heygen.com/avatar-iv.md)

### 3c. Template-based generation (branded UGC ad formats)

`POST https://api.heygen.com/v2/template/{template_id}/generate`. The `variables` object is
keyed by variable name; each entry has `name`, `type`, and `properties`.
(https://developers.heygen.com/template-api.md)

Variable types and their `properties`:
- **text** → `content` (string, max 10,000 chars)
- **image** → `url` OR `asset_id`; optional `fit` (contain/cover/crop/none)
- **video** → `url` OR `asset_id`; optional `play_style`, `fit`, `volume`
- **audio** → `url` OR `asset_id`
- **voice** → `voice_id` (required); optional `locale`
- **character** → `character_id`, `type` (avatar/talking_photo); optional alignment/corner

```json
POST https://api.heygen.com/v2/template/YOUR_TEMPLATE_ID/generate
{
  "title": "UGC ad - SummerSale",
  "caption": false,
  "dimension": { "width": 1080, "height": 1920 },
  "variables": {
    "script": {
      "name": "script", "type": "text",
      "properties": { "content": "This is the product that changed my routine." }
    },
    "avatar": {
      "name": "avatar", "type": "character",
      "properties": { "character_id": "Jason_public_3_20240312", "type": "avatar" }
    },
    "product_shot": {
      "name": "product_shot", "type": "image",
      "properties": { "url": "https://cdn.agencios.app/products/123.png", "fit": "contain" }
    }
  }
}
```

Response: `{ "error": null, "data": { "video_id": "763fca2469b98a65b351eqr8c449f4e8" } }`.
List templates: `GET /v2/templates`. Inspect a template's declared variables:
`GET /v2/template/{template_id}`. (https://developers.heygen.com/template-api.md)

### 3d. Polling / status

**v2/v1:** `GET https://api.heygen.com/v1/video_status.get?video_id=<id>`. Response envelope
is `{ code, data, message }`. Status values: `pending` / `processing` / `completed` /
`failed`. (https://apidog.com/blog/heygen-api/)

```json
{
  "code": 100,
  "data": {
    "id": "af273759...",
    "status": "completed",
    "video_url": "https://files.heygen.ai/.../video.mp4",
    "thumbnail_url": "https://files.heygen.ai/.../thumb.jpg",
    "gif_url": "https://files.heygen.ai/.../preview.gif",
    "caption_url": null,
    "duration": 12.34,
    "callback_id": "creative_8842",
    "error": null
  },
  "message": "Success"
}
```

On failure, `status` is `"failed"` and `error` is populated. `video_url` is a **presigned,
time-limited** URL — download promptly. (https://apidog.com/blog/heygen-api/)

**v3 equivalent:** `GET https://api.heygen.com/v3/videos/{video_id}` → `VideoDetail` with
`id`, `status`, `video_url`, `thumbnail_url`, `gif_url`, `captioned_video_url`,
`subtitle_url`, `duration`, `failure_code`, `failure_message`, `video_page_url`,
`created_at`, `completed_at`. (https://developers.heygen.com/reference/get-video.md)

### 3e. Webhook on completion (preferred over polling)

**Register (legacy v1):** `POST https://api.heygen.com/v1/webhook/endpoint.add` with
`{ "url": "...", "events": ["avatar_video.success", "avatar_video.fail"] }`; response
includes `endpoint_id`, `url`, `status`, `events`, and a **`secret`** for verification.
List with `GET /v1/webhook/endpoint.list`; available events via `GET /v1/webhook/webhook.list`.
(https://docs.heygen.com/reference/add-a-webhook-endpoint,
https://docs.heygen.com/docs/using-heygens-webhook-events)

```bash
curl https://api.heygen.com/v1/webhook/endpoint.add \
  -H 'Content-Type: application/json' \
  -H 'X-Api-Key: <key>' \
  -d '{"url":"https://agencios.app/webhooks/heygen","events":["avatar_video.success","avatar_video.fail"]}'
```

**Register (new v3):** `POST /v3/webhooks/endpoints` with `{ url, events, entity_id? }`;
response includes `endpoint_id`, `url`, `events`, `status` ("enabled"/"disabled"),
`created_at`, and `secret` (**only returned on create and rotate-secret — store it**).
Management: `GET /v3/webhooks/endpoints`, `PATCH /v3/webhooks/endpoints/{id}`,
`DELETE /v3/webhooks/endpoints/{id}`, `POST /v3/webhooks/endpoints/{id}/rotate-secret`,
`GET /v3/webhooks/event-types`. (https://developers.heygen.com/reference/create-webhook-endpoint.md,
https://developers.heygen.com/docs/webhooks.md)

**Available events:** `avatar_video.success`, `avatar_video.fail`,
`avatar_video_gif.success/.fail`, `avatar_video_caption.success/.fail`,
`video_translate.success/.fail`, `video_agent.success/.fail`, `personalized_video`,
`instant_avatar.success/.fail`, `photo_avatar_generation.success/.fail`,
`photo_avatar_train.success/.fail`, `photo_avatar_add_motion.success/.fail`,
`proofread_creation.success/.fail`, `live_avatar.success/.fail`.
(https://developers.heygen.com/docs/webhook-events.md)

**Inbound webhook payload** HeyGen POSTs to you
(https://developers.heygen.com/docs/webhook-events.md):

```json
{
  "event_id": "evt_abc123",
  "event_type": "avatar_video.success",
  "event_data": {
    "video_id": "vid_xyz789",
    "url": "https://files.heygen.com/video/vid_xyz789.mp4",
    "gif_download_url": "https://resource.heygen.ai/video/vid_xyz789/gif.gif",
    "video_page_url": "https://app.heygen.com/videos/vid_xyz789",
    "video_share_page_url": "https://app.heygen.com/share/vid_xyz789",
    "folder_id": null,
    "callback_id": "creative_8842"
  },
  "created_at": "2026-03-25T12:05:00Z"
}
```

**Signature verification** (https://developers.heygen.com/docs/webhooks.md):
- Header **`Heygen-Signature`** = hex-encoded **HMAC-SHA256** of the **raw request body**
  computed with your endpoint `secret`. Compare in constant time.
- Verify against **raw body bytes**, not re-serialized JSON (whitespace/key-order changes
  break the HMAC).
- Supporting headers: `Heygen-Timestamp` (reject stale deliveries, ~5-min window) and
  `Heygen-Event-Id` (dedupe retries — webhooks can be delivered more than once).

## 4. List avatars/voices endpoints

**`GET https://api.heygen.com/v2/avatars`** → `{ error, data: { avatars: [...],
talking_photos: [...] } }`. (https://developers.heygen.com/more-legacy-api.md,
https://docs.heygen.com/reference/list-avatars-v2)

```json
{
  "avatar_id": "Abigail_expressive_2024112501",
  "avatar_name": "Abigail (Upper Body)",
  "gender": "female",
  "preview_image_url": "https://files2.heygen.ai/avatar/v3/.../preview_target.webp",
  "preview_video_url": "https://files2.heygen.ai/avatar/v3/.../preview_video_target.mp4",
  "premium": false,
  "type": null,
  "tags": null
}
```

Talking-photo (Photo Avatar) objects: `talking_photo_id`, `talking_photo_name`,
`preview_image_url`. (https://docs.heygen.com/reference/list-avatars-v2)

**`GET https://api.heygen.com/v2/voices`** → each voice object (https://apidog.com/blog/heygen-api/):

```json
{
  "voice_id": "26b2064088674c80b1e5fc5ab1a068ec",
  "language": "English",
  "gender": "male",
  "name": "Rex",
  "preview_audio": "https://resource.heygen.ai/text_to_speech/....mp3",
  "support_pause": false,
  "emotion_support": true,
  "support_interactive_avatar": true
}
```

**v3 equivalents:** `GET /v3/voices` (fields: `voice_id`, `name`, `language`, `gender`,
`preview_audio_url`, `support_pause`, `support_locale`, `type`; paginated with
`has_more`/`next_token`) and avatar listing via
`GET /v3/avatars/looks?avatar_type=...&ownership=public`.
(https://developers.heygen.com/reference/list-voices.md, https://developers.heygen.com/photo-avatar.md)

**Photo Avatar / Avatar IV:** v3 consolidated these. Create a photo avatar with
`POST /v3/avatars` (`{ "type":"photo", "name":"...", "file": { "type":"url"|"asset_id",
"url"|"asset_id":"..." } }`), upload the source image via `POST /v3/assets` (returns
`asset_id`), then generate with `POST /v3/videos` using the returned `avatar_id` plus
Avatar-IV-only fields `motion_prompt` and `expressiveness`. The older multi-step v2 flow
(`POST /v2/photo_avatar/...`, train avatar groups) remains live until Oct 2026.
(https://developers.heygen.com/photo-avatar.md, https://developers.heygen.com/avatar-iv.md,
https://docs.heygen.com/docs/create-and-train-photo-avatar-groups)

## 5. Backend plan

Mirrors agencios conventions (vendors with `Client` + `Actions::<Verb>`; operations under
`app/services/operations/`; secrets in Rails encrypted credentials; Sidekiq;
`Controllers::Webhooks::*` → `Operations::*`). All service objects expose `.call`.

**Secrets** (`rails credentials:edit`):
```yaml
heygen:
  api_key: "..."          # X-Api-Key
  webhook_secret: "..."   # returned by endpoint.add / create-endpoint
```

**Data model — a `Creative` AR record:** `heygen_video_id` (string, indexed, unique),
`status` (enum: `queued`/`processing`/`completed`/`failed`), `avatar_id`, `voice_id`,
`script` (text), `template_id` (nullable), `callback_id` (your correlation id), `video_url`,
`thumbnail_url`, `gif_url`, `duration`, `failure_message`, tenant scope, timestamps. Use an
ActiveStorage attachment for the downloaded MP4.

**Class map — every HeyGen call → a concrete Action:**

| HeyGen API call | Action class |
|---|---|
| `POST /v2/video/generate` (or `/v3/videos`) | `Vendors::Heygen::Actions::GenerateVideo` |
| `POST /v2/template/{id}/generate` | `Vendors::Heygen::Actions::GenerateVideoFromTemplate` |
| `GET /v2/templates` | `Vendors::Heygen::Actions::ListTemplates` |
| `GET /v2/template/{id}` | `Vendors::Heygen::Actions::GetTemplate` |
| `GET /v2/avatars` | `Vendors::Heygen::Actions::ListAvatars` |
| `GET /v2/voices` | `Vendors::Heygen::Actions::ListVoices` |
| `GET /v1/video_status.get` | `Vendors::Heygen::Actions::GetVideoStatus` |
| `POST /v1/webhook/endpoint.add` (or `/v3/webhooks/endpoints`) | `Vendors::Heygen::Actions::AddWebhookEndpoint` |
| `POST /v3/avatars` (photo avatar) | `Vendors::Heygen::Actions::CreatePhotoAvatar` |
| `POST /v3/assets` (image upload) | `Vendors::Heygen::Actions::UploadAsset` |

**Orchestration:**
- `Operations::Creatives::GenerateUgcVideo` — entry point: takes a `Creative` (or its
  params), calls `Vendors::Heygen::Actions::GenerateVideo`, stores `heygen_video_id`, sets
  status `queued`, enqueues `PollHeygenVideoJob` as a safety net.
- `PollHeygenVideoJob` (Sidekiq) — calls `GetVideoStatus`; if `completed`, hands off to
  `Operations::Creatives::FinalizeUgcVideo` (download MP4 → attach → mark completed →
  broadcast); if still processing, re-enqueues with backoff; if `failed`, marks failed. The
  webhook is the fast path; this job is the fallback for missed webhooks.
- `Controllers::Webhooks::Heygen` — verifies signature, dedupes on `Heygen-Event-Id`, then
  delegates to `Operations::Creatives::FinalizeUgcVideo` on `avatar_video.success` / marks
  failed on `avatar_video.fail`.

**Client sketch:**

```ruby
module Vendors
  module Heygen
    class Client
      BASE = "https://api.heygen.com"

      def initialize
        @api_key = Rails.application.credentials.heygen[:api_key]
      end

      def post(path, body)
        request(Net::HTTP::Post, path) { |req| req.body = body.to_json }
      end

      def get(path)
        request(Net::HTTP::Get, path)
      end

      private

      def request(verb, path)
        uri = URI("#{BASE}#{path}")
        req = verb.new(uri)
        req["X-Api-Key"]    = @api_key
        req["Content-Type"] = "application/json"
        req["Accept"]       = "application/json"
        yield req if block_given?
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
        body = JSON.parse(res.body)
        raise Vendors::Heygen::Error, body.dig("error") if body["error"].present?
        body
      end
    end
  end
end
```

**Action sketch:**

```ruby
module Vendors
  module Heygen
    module Actions
      class GenerateVideo
        def self.call(...) = new(...).call

        def initialize(avatar_id:, voice_id:, script:, callback_id:,
                       dimension: { width: 1080, height: 1920 },
                       avatar_style: "normal", background: { type: "color", value: "#FFFFFF" },
                       test: false)
          @params = {
            video_inputs: [{
              character: { type: "avatar", avatar_id:, avatar_style: },
              voice:     { type: "text", input_text: script, voice_id: },
              background:
            }],
            dimension:, callback_id:, test:
          }
        end

        def call
          resp = Client.new.post("/v2/video/generate", @params)
          resp.dig("data", "video_id")
        end
      end
    end
  end
end
```

**Webhook handler sketch** (controller stays thin; service does the work):

```ruby
# app/controllers/webhooks/heygen_controller.rb
class Webhooks::HeygenController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authentication

  def receive
    raw = request.body.read
    Controllers::Webhooks::Heygen::Receive.call(raw, request.headers["Heygen-Signature"])
    head :ok
  rescue Controllers::Webhooks::Heygen::InvalidSignature
    head :bad_request
  end
end

# app/services/controllers/webhooks/heygen/receive.rb
module Controllers
  module Webhooks
    module Heygen
      class InvalidSignature < StandardError; end

      class Receive < Base
        def initialize(raw_body, signature)
          @raw_body  = raw_body
          @signature = signature
        end

        def call
          verify!
          event = JSON.parse(@raw_body)
          data  = event["event_data"]
          creative = Creative.find_by(heygen_video_id: data["video_id"])
          return unless creative

          case event["event_type"]
          when "avatar_video.success"
            Operations::Creatives::FinalizeUgcVideo.call(creative, url: data["url"])
          when "avatar_video.fail"
            creative.update!(status: :failed)
          end
        end

        private

        def verify!
          secret   = Rails.application.credentials.heygen[:webhook_secret]
          expected = OpenSSL::HMAC.hexdigest("SHA256", secret, @raw_body)
          unless ActiveSupport::SecurityUtils.secure_compare(expected, @signature.to_s)
            raise InvalidSignature
          end
        end
      end
    end
  end
end
```

Register the webhook once (rake task / initializer) via
`Vendors::Heygen::Actions::AddWebhookEndpoint` pointing at
`https://agencios.app/webhooks/heygen`, capture the returned `secret`, store it in
credentials.

## 6. Pricing/credits → maps to agencios usage-based billing (per video generation)

HeyGen API billing is **pay-as-you-go from a prepaid USD wallet** — no subscription; check
balance via `GET /v3/users/me → wallet`. Pay-as-you-go credits **expire 12 months** after
purchase; start with as little as **$5**. (https://developers.heygen.com/docs/pricing.md,
https://help.heygen.com/en/articles/10060327-heygen-api-pricing-explained)

**Per-second cost** (https://developers.heygen.com/docs/pricing.md):

| Feature | Cost | $1 buys | Per minute |
|---|---|---|---|
| Standard avatar video (720p/1080p) | rule of thumb | ~1 min | **~$1.00** |
| Avatar III Photo Avatar | $0.0433/sec | ~23 sec | ~$2.60 |
| Avatar IV Photo Avatar | $0.05/sec | ~20 sec | **$3.00** (help-center quotes "$4/min" for 1080p Avatar IV) |
| Avatar IV Digital Twin | $0.0667/sec | ~15 sec | ~$4.00 |
| Video Agent | $0.0333/sec | ~30 sec | ~$2.00 |
| Video Translation | $0.0333/sec | ~30 sec | ~$2.00 |
| Text-to-Speech | $0.000667/sec | ~1,499 sec | negligible |
| Avatar Creation (photo avatar) | $1.00 per call | — | per avatar |

The help-center frames it as **$1 = 1 minute** standard, **$4/min** Avatar IV 1080p,
**$2/min** translation/video-agent. Treat the per-second `pricing.md` figures as precise.
(https://help.heygen.com/en/articles/10060327-heygen-api-pricing-explained)

**Legacy plans:** Old subscription API plans (**API Pro**, **API Scale**) are deprecated;
existing subscribers may stay but cannot restore them once cancelled; legacy credits expired
after 30 days vs 12 months for pay-as-you-go.
(https://help.heygen.com/en/articles/10060327-heygen-api-pricing-explained)

**Enterprise:** adds scalability, dedicated dev support, Digital Twin Creation API, Proofread
API (Enterprise-only), discounted rates; sales-negotiated.
(https://www.heygen.com/enterprise-api)

**Mapping to agencios usage-based billing:** cost is **deterministic per output second**, and
the status/webhook payload returns `duration`, so you can compute exact COGS per render:
`heygen_cost = duration_seconds × rate(engine)`. Record it on the `Creative` (e.g.
`heygen_cost_cents`, `engine`), then bill the agency client a marked-up per-video or
per-second price. The natural metering hook is `Operations::Creatives::FinalizeUgcVideo` —
once `duration` is known, write the cost line and emit a usage record into your Stripe
usage-based billing flow (the `video_generation` meter). Buy HeyGen wallet credit in bulk and
resell at markup; monitor `wallet` balance via a scheduled job and alert before it runs dry.

## 7. Gotchas & testing checklist

- **Docs moved.** Use `developers.heygen.com` (add `.md` for clean markdown).
  `docs.heygen.com/*` only shows a migration banner. Best URL map:
  https://developers.heygen.com/llms.txt
- **v2 vs v3 — pick one and commit.** v2 (`/v2/video/generate`, `video_inputs`, `dimension`)
  is supported only **through Oct 31, 2026**. For new work target **v3** (`/v3/videos`,
  `aspect_ratio`+`resolution`, `script`). `Vendors::Heygen::Client` should abstract the
  version so you can swap.
- **Always async.** Generate returns a `video_id`, not a video. Never block a request waiting
  for render. Webhook = fast path, `PollHeygenVideoJob` = fallback.
- **Verify webhook signatures over RAW body.** Capture `request.body.read` before any JSON
  parse/middleware reserializes it; HMAC-SHA256 with the endpoint `secret`; constant-time
  compare; header is `Heygen-Signature`. Dedupe on `Heygen-Event-Id`; reject stale
  `Heygen-Timestamp`. (https://developers.heygen.com/docs/webhooks.md)
- **Webhook secret is shown once** — returned only on create/rotate-secret. Store immediately.
- **Video URLs expire** — `video_url` is presigned/time-limited; download to your own storage
  in `FinalizeUgcVideo`, don't hot-link.
- **Use `test: true` (v2) during dev** to render previews without burning wallet quota.
- **Script length cap:** `input_text` < 5000 chars per scene (v2); template text vars <
  10,000 chars.
- **Avatar listing is large/paginated and not exhaustive** — cache the list, refresh
  periodically.
- **Fund the wallet first** — generation deducts from the prepaid wallet; empty wallet fails
  real (non-test) renders. Monitor `wallet` via `GET /v3/users/me`.
- **Local webhook testing** — the docs use `smee.io` to tunnel webhooks during development.

**Checklist:** (1) generate API key + verify with `/v1/user/me`; (2) fund wallet $5; (3)
`ListAvatars`/`ListVoices`, cache; (4) `GenerateVideo` with `test:true`; (5) poll
`GetVideoStatus` to `completed`; (6) register webhook, store secret; (7) verify signature on
a real success event; (8) `FinalizeUgcVideo` downloads + attaches MP4; (9) record
`duration`→cost; (10) flip `test:false` for production.

---

### Findings I could NOT fully verify from official docs

1. **Free-tier API key eligibility** — docs never explicitly state whether a brand-new free
   account (zero wallet balance) can generate a working API key. Assume key generation is
   allowed but real renders need a funded wallet.
   (https://developers.heygen.com/docs/api-key.md, https://developers.heygen.com/docs/pricing.md)
2. **Avatar IV per-minute price conflict** — `pricing.md` lists Avatar IV Photo Avatar at
   $0.05/sec ($3/min); help-center says $4/min for Avatar IV 1080p. Likely different SKUs
   (Photo Avatar vs Digital Twin at $0.0667/sec ≈ $4/min). Confirm exact engine/resolution
   SKU before basing margins on it.
3. **Legacy v1 webhook `secret` field / signature header** — confirmed the secret/HMAC
   mechanism from the **v3** webhook docs (`Heygen-Signature`). If you stay on the v1 webhook
   registration path, double-check the exact signature header it uses.
4. **Exact v2 `GET /v2/avatars` / `GET /v2/voices` envelopes** — v2 reference pages 404 on
   the new site; field *names* reconstructed from the legacy doc + search snippets + apidog
   mirror are reliable, but confirm the wrapping envelope (`data.avatars` vs flat array) with
   one live call before coding the parser.
5. **Photo Avatar v2 train/group endpoints** — v3 consolidated into `POST /v3/avatars`; the
   older multi-step v2 flow exists per legacy docs but those exact paths are now behind the
   migration banner and full current schemas weren't fetchable.
