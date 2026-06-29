# LinkedIn Publishing & Analytics — Integration Guide (2025–2026)

A complete, current (verified June 2026 against `learn.microsoft.com/linkedin` and `developer.linkedin.com`) guide for programmatically **publishing posts** (member profile + organization/Company Page) and **reading analytics** from LinkedIn, mapped to the **agencios** Rails 8.1 backend.

All API behavior below is tied to the **Posts API** (`/rest/posts`) — the current, versioned API that **replaces the legacy `ugcPosts` and `shares` APIs**. Do not build new integrations on `ugcPosts`/`shares`/`v2/assets`; they are superseded by `rest/posts`, `rest/images`, and `rest/videos`. ([Posts API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-06))

> **Two halves of this doc.** Part A (§1–§3) is the *portal clickpath* — paste it into the Claude Chrome extension so a browser agent can drive `developer.linkedin.com`. Part B (§4–§10 + the API table) is the *backend plan* for the Rails app. They share the same scope/product vocabulary.

---

## 0. What you'll build

A `Vendors::Linkedin` wrapper plus `Operations::*` side-effect classes that let a workspace:

1. Connect a LinkedIn account via **3-legged OAuth** (authorization code → access token, ~60-day TTL, optional 1-year refresh token), storing tokens encrypted on a `SocialAccount` model.
2. Resolve the **author URN** — `urn:li:person:{id}` for the member, `urn:li:organization:{id}` for each Company Page the member administers.
3. **Publish** to the member profile and to Company Pages via `POST /rest/posts`: text, single image, video, and article/link shares.
4. **Read analytics** for Company Pages via `organizationalEntityShareStatistics` (post/share metrics) and `organizationalEntityFollowerStatistics` (follower counts & demographics).

What LinkedIn **does not** give you (be explicit with stakeholders):
- **No member-profile analytics API.** Organic post/share & follower statistics are **organization-only**. There is no equivalent endpoint for a personal profile's post impressions.
- **No general publishing webhooks.** Webhooks exist only for a narrow set (org social-action notifications, Lead Sync) and require their own approval — see §8.
- **Organization posting + all org analytics require partner approval** (Community Management API). Member-only posting (`w_member_social`) is self-serve via the "Share on LinkedIn" product. See §2–§3.

---

# Part A — Portal setup (browser clickpath)

## 1. Accounts & prerequisites

Before touching the developer portal you need three things:

1. **A personal LinkedIn account** (real, logged in). LinkedIn apps are owned by a member, not an anonymous org.
2. **A LinkedIn Company Page you administer.** To post as / read analytics for an organization, the authenticated member must hold a page role of **ADMINISTRATOR**, **DIRECT_SPONSORED_CONTENT_POSTER**, or **CONTENT_ADMIN** on that page. Analytics specifically requires **ADMINISTRATOR**. ([Posts API permissions](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-06); [Share Statistics permissions](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/share-statistics?view=li-lms-2026-06))
   - Create one at `linkedin.com/company/setup/new/` if you don't have it (needs a verified personal profile with some connections).
3. **A legally registered entity.** The Community Management API is **only granted to registered legal entities** (LLC, Corp, 501(c), etc.), **not individual developers**. You'll supply company details in the access form. ([Increasing Access](https://learn.microsoft.com/en-us/linkedin/marketing/increasing-access?view=li-lms-2025-11))

## 2. Create the app (exact clickpath)

> Paste this section into the Claude Chrome extension; it is a literal click script.

1. Go to **`https://www.linkedin.com/developers/apps`** and click **Create app**.
2. Fill the form:
   - **App name** → e.g. `agencios`.
   - **LinkedIn Page** → type your Company Page name and **select it**. *This association is mandatory* — it links the app to the org and is what later unlocks org scopes. (If the field stays empty you cannot proceed; a page admin must do this.)
   - **App logo** → upload (required to publish the app).
   - Accept the API Terms of Use → **Create app**.
3. **Verify the app ↔ Page association.** On the new app's **Settings** tab, in the **Company** box click **Verify**. This generates a verification URL — open it **as a Page admin** and click **Verify**. The app now shows "Verified". (Org products will not approve without this.)
4. Go to the **Auth** tab. Note the **Client ID** and **Client Secret** (you'll store the secret in Rails credentials — §5). Under **OAuth 2.0 settings → Authorized redirect URLs**, add your callback, e.g. `https://app.agencios.com/auth/linkedin/callback` and (for local) `http://localhost:3000/auth/linkedin/callback`. Redirect URLs must be absolute HTTPS (localhost http is accepted for dev), have no `#`, and query params are ignored. ([3-legged OAuth — Step 1](https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow))
5. Go to the **Products** tab and request, in this order:
   - **Sign In with LinkedIn using OpenID Connect** → grants `openid profile email`. **Self-serve, instant.** Needed to identify the member and build their person URN (§5). ([Sign In with OpenID Connect](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2))
   - **Share on LinkedIn** → grants `w_member_social`. **Self-serve, instant.** Lets you post to the **authenticated member's own profile**. ([Share on LinkedIn product](https://developer.linkedin.com/product-catalog/marketing))
   - **Community Management API** → grants the **organization** scopes (`r_organization_social`, `w_organization_social`, `rw_organization_admin`, `r_organization_admin`). **Requires LinkedIn review/approval.** Click **Request access**, then complete the access form (company legal name, use case, website). This is the **Marketing Developer Platform** gate for org posting + org analytics. ([Community Management product](https://developer.linkedin.com/product-catalog/marketing/community-management-api); [Increasing Access](https://learn.microsoft.com/en-us/linkedin/marketing/increasing-access?view=li-lms-2025-11))
6. **Check approval status** on the **Products** tab. Community Management starts in **Development Tier** (build/test, capped quotas) once approved; you apply for **Standard Tier** for production volume. Approval can take **several days**. The org scopes will *not* appear on the Auth tab until approved — requesting them before then yields an **"unauthorized scope"** error during OAuth. ([Increasing Access](https://learn.microsoft.com/en-us/linkedin/marketing/increasing-access?view=li-lms-2025-11))

> **Only request Community Management *Development Tier* on a fresh app** that has no other API products attached — LinkedIn explicitly warns against mixing it onto an app that already holds other products.

## 3. Scopes & products

| Scope | Granted by Product | Approval | What it does |
|---|---|---|---|
| `openid` | Sign In with LinkedIn (OIDC) | Self-serve | Enables OIDC; returns an ID token. |
| `profile` | Sign In with LinkedIn (OIDC) | Self-serve | Lite profile (id, name, picture) via `/v2/userinfo`. |
| `email` | Sign In with LinkedIn (OIDC) | Self-serve | Member email via `/v2/userinfo`. |
| `w_member_social` | Share on LinkedIn | Self-serve | Post/comment/like **as the authenticated member** (their own profile). |
| `r_member_social` | (restricted) | **Restricted / approved only** | Read a member's own posts. Not generally granted. |
| `r_organization_social` | Community Management API | **Partner approval** | Read an org's posts/comments/likes (member must hold a page role). |
| `w_organization_social` | Community Management API | **Partner approval** | Post/comment/like **as an organization** (ADMIN / DSC poster / content admin). |
| `rw_organization_admin` | Community Management API | **Partner approval** | Manage Pages **and retrieve reporting** — required for share & follower **statistics** (ADMINISTRATOR role). |
| `r_organization_admin` | Community Management API | **Partner approval** | Read Page admin/ACL info. |

Sources: [Posts API permissions](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-06), [Share Statistics permissions](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/share-statistics?view=li-lms-2026-06), [Follower Statistics permissions](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/follower-statistics?view=li-lms-2026-06), [Sign In with OIDC](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2).

**Critical nuance to design around:** publishing as an org needs `w_organization_social`, but **org analytics needs `rw_organization_admin`** (not the `r_organization_social`/`r_member_social` you might assume). Request all four org scopes together so a single OAuth grant covers post + read + stats. A reasonable production scope set:

```
openid profile email w_member_social r_organization_social w_organization_social rw_organization_admin
```

Requesting any scope your app isn't provisioned for produces a `401 Invalid scope` at `/oauth/v2/authorization`. If you change the scope set later, **users must re-authenticate** — old tokens are invalidated. ([3-legged OAuth](https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow))

---

# Part B — Backend implementation (Rails 8.1, "agencios")

## 4. OAuth flow (3-legged)

**Endpoints** ([authorization-code-flow](https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow)):

### Step 1 — send the member to authorize
```
GET https://www.linkedin.com/oauth/v2/authorization
  ?response_type=code
  &client_id={CLIENT_ID}
  &redirect_uri={URL-encoded callback}
  &state={random CSRF token, store in session}
  &scope={URL-encoded, space-delimited scopes}
```
Example `scope` value: `openid%20profile%20email%20w_member_social%20w_organization_social%20rw_organization_admin`.
On approval LinkedIn redirects to `redirect_uri?code=...&state=...`. **Validate `state`** (else return 401). The `code` is single-use and lives **30 minutes**.

### Step 2 — exchange code for tokens
```
POST https://www.linkedin.com/oauth/v2/accessToken
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code={code from step 1}
&client_id={CLIENT_ID}
&client_secret={CLIENT_SECRET}
&redirect_uri={same callback as step 1}
```
Response:
```json
{
  "access_token": "AQ...",
  "expires_in": 5184000,            // 60 days, in seconds
  "refresh_token": "AQ...",         // only if your app has refresh tokens enabled
  "refresh_token_expires_in": 31536000,  // ~365 days
  "scope": "openid,profile,email,w_member_social,..."
}
```

### Token lifetimes & refresh
- **Access token: 60 days** (`expires_in` = 5184000s). ([authorization-code-flow](https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow))
- **Refresh token: ~365 days**, and a refresh keeps the *original* refresh-token TTL (it does not reset to 365). Refreshing returns a fresh 60-day access token. ([programmatic-refresh-tokens](https://learn.microsoft.com/en-us/linkedin/shared/authentication/programmatic-refresh-tokens))
- **Programmatic refresh tokens are gated** — available only to a limited set of partners. If your app lacks them, "refresh" means re-running the 3-legged flow (the consent screen is **bypassed** as long as the member is still logged into LinkedIn and the grant is intact). Design `SocialAccount#access_token_expired?` to trigger either a programmatic refresh (if enabled) or a re-auth prompt.

Refresh request (when enabled):
```
POST https://www.linkedin.com/oauth/v2/accessToken
Content-Type: application/x-www-form-urlencoded
grant_type=refresh_token&refresh_token={...}&client_id={...}&client_secret={...}
```

### Headers used on ALL `rest/*` API calls (not the OAuth calls)
Every versioned API request must carry:
```
Authorization: Bearer {access_token}
LinkedIn-Version: 202606            # YYYYMM; see versioning below
X-Restli-Protocol-Version: 2.0.0
Content-Type: application/json      # for POST/PARTIAL_UPDATE bodies
```
- **`LinkedIn-Version`** is **mandatory** and uses `YYYYMM`. A missing header returns an error; a **sunset** version (e.g. `202401`) also errors. Versions are published monthly and supported **≥ 1 year** before sunset. Latest as of writing: **`202606`** (June 2026). The base path is `https://api.linkedin.com/rest/`. Keep the version as an app constant and bump it ~yearly. ([versioning](https://learn.microsoft.com/en-us/linkedin/marketing/versioning?view=li-lms-2026-06))
- **`X-Restli-Protocol-Version: 2.0.0`** is required on all `rest/*` calls. It also dictates URN/list encoding in query strings (see §7).

> **agencios mapping:** `Vendors::Linkedin::Client` injects these three headers on every request and holds `LINKEDIN_VERSION = "202606"`. OAuth token exchange/refresh lives in `Operations::Integrations::Linkedin::RefreshToken` (or `ExchangeCode`), invoked from the OAuth callback controller and from a Sidekiq pre-flight check before any publish job.

## 5. Store credentials

**Rails encrypted credentials** (`rails credentials:edit`):
```yaml
linkedin:
  client_id: "xxxxxxxxxxxx"
  client_secret: "xxxxxxxxxxxxxxxx"
```
Never put these in `.env`. Read via `Rails.application.credentials.dig(:linkedin, :client_id)`.

**`SocialAccount` model** (`belongs_to :workspace`), all token fields encrypted with `encrypts`:

| Column | Type | Notes |
|---|---|---|
| `provider` | string | `"linkedin"` |
| `access_token` | text (encrypted) | 60-day token; plan for ≥1000 chars |
| `refresh_token` | text (encrypted) | ~365-day token, if granted |
| `access_token_expires_at` | datetime | `now + expires_in.seconds` |
| `refresh_token_expires_at` | datetime | `now + refresh_token_expires_in.seconds` |
| `scopes` | string | space- or comma-delimited granted scopes |
| `member_id` | string | the `sub` from `/v2/userinfo`, e.g. `782bbtaQ` |
| `member_urn` | string | `urn:li:person:{member_id}` |
| `member_name` | string | display name (from userinfo) |
| `member_email` | string | from userinfo (optional) |
| `default_org_id` | string | bare org id, e.g. `5515715` |
| `default_org_urn` | string | `urn:li:organization:{default_org_id}` |

**Resolving the author URNs after OAuth:**

1. **Person URN** — call `GET https://api.linkedin.com/v2/userinfo` with the Bearer token. The `sub` field is the **bare member id** (e.g. `"782bbtaQ"`); build `urn:li:person:782bbtaQ`. The full response: ([Sign In with OIDC](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2))
   ```json
   { "sub": "782bbtaQ", "name": "John Doe", "given_name": "John",
     "family_name": "Doe", "picture": "https://...", "locale": "en-US",
     "email": "doe@email.com", "email_verified": true }
   ```
   > `userinfo` does **not** carry a `LinkedIn-Version` header — it's a `/v2/` endpoint, just `Authorization: Bearer`.

2. **Organization URN(s)** — list the Pages the member administers via the ACL finder ([Organization Access Control by Role](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/organization-access-control-by-role?view=li-lms-2026-06)):
   ```
   GET https://api.linkedin.com/rest/organizationAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED
   Headers: Bearer + LinkedIn-Version + X-Restli-Protocol-Version: 2.0.0
   ```
   Each element has `organizationTarget: "urn:li:organization:{id}"`. Persist these as the orgs the workspace can post to / pull analytics for. (Requires `rw_organization_admin` or `r_organization_admin`.)

> **agencios mapping:** store one `SocialAccount` per connected LinkedIn member per workspace. If a workspace manages multiple Pages, either store the org list in a child table or a JSON column; pick the active author URN at publish time.

## 6. Publishing flow — Posts API

All publishing is `POST https://api.linkedin.com/rest/posts` with the §4 headers. **Author** is the only field that differs between member and org posts:
- member: `"author": "urn:li:person:{member_id}"` (needs `w_member_social`)
- org: `"author": "urn:li:organization:{org_id}"` (needs `w_organization_social` + page role)

Success = **`201`**; the new post URN is in the **`x-restli-id` response header** (e.g. `urn:li:share:684...` or `urn:li:ugcPost:684...`). Persist it. ([Posts API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-06))

### 6a. Text-only post
```json
{
  "author": "urn:li:organization:5515715",
  "commentary": "Sample text Post",
  "visibility": "PUBLIC",
  "distribution": {
    "feedDistribution": "MAIN_FEED",
    "targetEntities": [],
    "thirdPartyDistributionChannels": []
  },
  "lifecycleState": "PUBLISHED",
  "isReshareDisabledByAuthor": false
}
```
For a member post, swap `author` to `urn:li:person:{id}`. `commentary` supports **mentions** `@[Name](urn:li:organization:2414183)` and **hashtags** `#coding`. ([Posts API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-06))

### 6b. Single image (3 steps)
Image upload uses **`/rest/images?action=initializeUpload`** (the current Images API; it **replaces the old `v2/assets registerUpload`**). ([Images API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/images-api?view=li-lms-2026-06))

**Step 1 — initialize:**
```
POST https://api.linkedin.com/rest/images?action=initializeUpload
```
```json
{ "initializeUploadRequest": { "owner": "urn:li:organization:5583111" } }
```
`owner` is the **post author URN** (person or org). Response:
```json
{ "value": {
    "uploadUrlExpiresAt": 1650567510704,
    "uploadUrl": "https://www.linkedin.com/dms-uploads/.../0?...",
    "image": "urn:li:image:C4E10AQFoyyAjHPMQuQ"
} }
```

**Step 2 — upload the binary** to `uploadUrl` (no LinkedIn headers needed on this dms-uploads URL beyond auth in the signed URL; send raw bytes):
```
PUT {uploadUrl}
Content-Type: image/jpeg      (or image/png, image/gif)
<binary image bytes>
```
Supported: JPG/PNG/GIF, < 36,152,320 px (GIF ≤ 250 frames). Note: `SYNCHRONOUS_UPLOAD` is **not** supported; the asset processes async — poll `GET /rest/images/{urn}` for `status: AVAILABLE` if you need confirmation before posting.

**Step 3 — create the post** referencing the image URN in `content.media.id`:
```json
{
  "author": "urn:li:organization:5515715",
  "commentary": "test strings!",
  "visibility": "PUBLIC",
  "distribution": { "feedDistribution": "MAIN_FEED", "targetEntities": [], "thirdPartyDistributionChannels": [] },
  "content": { "media": { "altText": "alt text for a11y", "id": "urn:li:image:C5610AQFj6TdYowm17w" } },
  "lifecycleState": "PUBLISHED",
  "isReshareDisabledByAuthor": false
}
```
(For **multiple images** use the MultiImage API; org carousels are not supported organically. ([Posts API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-06)))

### 6c. Video (4 steps)
Video uses **`/rest/videos`** (replaces `v2/assets`). Multipart upload in 4 MB parts. ([Videos API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/videos-api?view=li-lms-2026-06))

**Step 1 — initialize:**
```
POST https://api.linkedin.com/rest/videos?action=initializeUpload
```
```json
{ "initializeUploadRequest": {
    "owner": "urn:li:organization:2414183",
    "fileSizeBytes": 1055736,
    "uploadCaptions": false,
    "uploadThumbnail": false
} }
```
Response gives a `video` URN, a `uploadToken`, and an `uploadInstructions` array (one entry per 4 MB part, each with `uploadUrl`, `firstByte`, `lastByte`):
```json
{ "value": {
    "uploadUrlsExpireAt": 1633234498985,
    "video": "urn:li:video:C5505AQH-oV1qvnFtKA",
    "uploadInstructions": [ { "uploadUrl": "https://www.linkedin.com/dms-uploads/...", "firstByte": 0, "lastByte": 4194303 } ],
    "uploadToken": ""
} }
```

**Step 2 — split & upload each part** (`split -b 4194303`), `PUT` each chunk to its `uploadUrl` with `Content-Type: application/octet-stream`. **Capture the `etag` response header for every part** — you need them in order.

**Step 3 — finalize:**
```
POST https://api.linkedin.com/rest/videos?action=finalizeUpload
```
```json
{ "finalizeUploadRequest": {
    "video": "urn:li:video:C5505AQHErI8lGthkfA",
    "uploadToken": "",
    "uploadedPartIds": ["<etag-part-1>", "<etag-part-2>"]
} }
```
`uploadedPartIds` must be the ETags **in upload order**.

**Step 4 — create the post** referencing the video URN (video processes async; `GET /rest/videos/{urn}` until `status: AVAILABLE`):
```json
{
  "author": "urn:li:organization:5515715",
  "commentary": "Sample video Post",
  "visibility": "PUBLIC",
  "distribution": { "feedDistribution": "MAIN_FEED", "targetEntities": [], "thirdPartyDistributionChannels": [] },
  "content": { "media": { "title": "title of the video", "id": "urn:li:video:C5F10AQGKQg_6y2a4sQ" } },
  "lifecycleState": "PUBLISHED",
  "isReshareDisabledByAuthor": false
}
```
Video limits: MP4, 3s–30min, 75 KB–500 MB (init supports up to 5 GB multipart). ([Videos API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/videos-api?view=li-lms-2026-06))

### 6d. Article / link share
The Posts API does **not** scrape URLs — you must supply the article fields yourself. Optional thumbnail must be an image URN uploaded via §6b. ([Posts API](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-06))
```json
{
  "author": "urn:li:organization:5515715",
  "commentary": "test article post",
  "visibility": "PUBLIC",
  "distribution": { "feedDistribution": "MAIN_FEED", "targetEntities": [], "thirdPartyDistributionChannels": [] },
  "content": {
    "article": {
      "source": "https://example.com/post",
      "thumbnail": "urn:li:image:C49klciosC89",
      "title": "Article title",
      "description": "Article description"
    }
  },
  "lifecycleState": "PUBLISHED",
  "isReshareDisabledByAuthor": false
}
```

### Other ops on a post
- **Edit:** `POST /rest/posts/{urlencoded-urn}` with header `X-RestLi-Method: PARTIAL_UPDATE` and a `{ "patch": { "$set": { "commentary": "..." } } }` body → `204`. Only `commentary`, CTA label/landing page, `lifecycleState`, `adContext` are editable.
- **Delete:** `DELETE /rest/posts/{urlencoded-urn}` with `X-RestLi-Method: DELETE` → `204` (idempotent).
- **Reshare:** add `"reshareContext": { "parent": "urn:li:share:..." }`.

> **agencios mapping:** `Vendors::Linkedin::Actions::CreatePost` (text/article), `::UploadImage` + `::UploadVideo` (the multi-step asset flows), `::DeletePost`, `::UpdatePost`. Orchestration (resolve author, upload media, poll for AVAILABLE, create post, persist `x-restli-id`) lives in `Operations::Linkedin::PublishPost`, run from a Sidekiq job. The media-upload step talks to non-`rest` dms-upload URLs, so keep it in a dedicated client method that does **not** inject the versioned headers.

## 7. Analytics flow (organization only)

Both endpoints are **organic only** (sponsored stats live in Ad Analytics), **org-only** (no member equivalent), require **`rw_organization_admin`** (ADMINISTRATOR role), and accept either lifetime (omit `timeIntervals`) or time-bound (include it) queries. Share statistics cover a **rolling 12-month window**; follower time-bound stats run from 12 months ago to ~2 days ago.

### 7a. Share / post statistics — `organizationalEntityShareStatistics`
```
GET https://api.linkedin.com/rest/organizationalEntityShareStatistics
    ?q=organizationalEntity&organizationalEntity=urn%3Ali%3Aorganization%3A2414183
Headers: Bearer + LinkedIn-Version + X-Restli-Protocol-Version: 2.0.0
```
- **Lifetime, aggregate:** as above. Response:
  ```json
  { "elements": [ {
      "organizationalEntity": "urn:li:organization:2414183",
      "totalShareStatistics": {
        "impressionCount": 14490816, "uniqueImpressionsCount": 9327,
        "clickCount": 109276, "likeCount": 52, "commentCount": 70,
        "shareCount": 0, "engagement": 0.00754947
  } } ] }
  ```
- **Time-bound:** add `timeIntervals=(timeRange:(start:{ms},end:{ms}),timeGranularityType:DAY)` (or `MONTH`). Each element then carries a `timeRange`.
- **Per-post:** add `shares=List(urn%3Ali%3Ashare%3A...)` **or** `ugcPosts[0]=urn:li:ugcPost:...` to get stats for specific posts (lifetime only; time-bound not supported per-share). Posts with zero activity are omitted (treat as all-zero).

**Metrics returned** (`totalShareStatistics`): `impressionCount`, `uniqueImpressionsCount`, `clickCount`, `likeCount`, `commentCount`, `shareCount`, `engagement` (clicks+likes+comments+shares ÷ impressions). **No pagination** on this endpoint. ([Share Statistics](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/share-statistics?view=li-lms-2026-06))

> For **up-to-the-minute like/comment counts** matching the feed, use the `socialActions` endpoint instead of waiting on aggregated stats.

### 7b. Follower statistics — `organizationalEntityFollowerStatistics`
```
GET https://api.linkedin.com/rest/organizationalEntityFollowerStatistics
    ?q=organizationalEntity&organizationalEntity=urn%3Ali%3Aorganization%3A2414183
```
- **Lifetime (segmented):** returns demographic breakdowns — `followerCountsByGeoCountry`, `…ByGeo`, `…ByIndustry`, `…ByFunction`, `…BySeniority`, `…ByStaffCountRange`, `…ByAssociationType` (top 100 per facet), each with `organicFollowerCount` / `paidFollowerCount`. Use `organicFollowerCount` (it's the rolled-up total) for demographics.
- **Time-bound:** add `timeIntervals=(...)` with granularity `DAY`/`WEEK`/`MONTH` → returns `followerGains: { organicFollowerGain, paidFollowerGain }` per interval (no demographic breakdown when time-bound).
- **Total follower count is NOT here** anymore — get it from the `networkSizes` API under Organization Lookup.

Permission: **`rw_organization_admin`**. ([Follower Statistics](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/follower-statistics?view=li-lms-2026-06))

> **URN encoding (Rest.li 2.0):** URNs and lists in query strings must be URL-encoded — `urn:li:organization:123` → `urn%3Ali%3Aorganization%3A123`; multiple ids use `List(...)`. `Vendors::Linkedin::Client` should encode these centrally.

> **agencios mapping:** `Vendors::Linkedin::Actions::FetchShareStatistics`, `::FetchPostStatistics` (per-post), `::FetchFollowerStatistics`. A Sidekiq cron (`Operations::Linkedin::SyncAnalytics`) pulls lifetime + last-N-days per connected org and stores snapshots; respect the 12-month window when backfilling.

## 8. Webhooks

LinkedIn has a **deliberately limited** webhook story — there is **no webhook for "post published," post metrics, or follower changes.** Webhooks exist only for narrow, separately-approved use cases (notably **organization social-action notifications** — likes/comments on org posts — and **Lead Sync** form submissions). They are gated behind their own product approval and require endpoint URL validation (LinkedIn sends a challenge you echo back). ([Webhook validation](https://learn.microsoft.com/en-us/linkedin/shared/api-guide/webhook-validation))

**Practical consequence for agencios:** treat analytics as **poll-based** (scheduled Sidekiq sync, §7). Do not architect around push notifications for impressions/engagement — they don't exist. Only build a webhook receiver if you specifically pursue org social-action notifications, and budget for a separate access request.

## 9. Rate limits & gotchas

- **Throttle tiers (two layers):** every endpoint enforces **per-application** *and* **per-member** daily quotas, resetting at **midnight UTC**. Community Management **Development Tier** quotas were raised to ~**500 req/app** and ~**100 req/member** per day; **Standard Tier** lifts these for production. Apps hitting 75% of an app-level quota get an email alert (1–2h delayed). Over-limit → **`429 TOO_MANY_REQUESTS`** — back off and retry. ([Rate limits](https://learn.microsoft.com/en-us/linkedin/shared/api-guide/concepts/rate-limits); [Increasing Access](https://learn.microsoft.com/en-us/linkedin/marketing/increasing-access?view=li-lms-2025-11))
- **`LinkedIn-Version` is required on every `rest/*` call.** Missing → error; sunset version → error. Keep `202606` current; bump within the 1-year support window.
- **`X-Restli-Protocol-Version: 2.0.0` is required** and changes how you encode URNs/Lists in query strings.
- **Partner approval gates org posting *and* org analytics.** Without Community Management approval the org scopes won't even appear at the OAuth step ("unauthorized scope"). Member posting (`w_member_social`) works self-serve.
- **Member analytics don't exist.** Don't promise post-impression dashboards for personal profiles.
- **No URL scraping** for article posts — supply title/description/thumbnail yourself (§6d).
- **Asset uploads are async** — image/video must reach `status: AVAILABLE` before (or as) you post; build polling/retry.
- **Scope changes invalidate tokens** — any change to the requested scope set forces re-auth.
- **Authorization code lives 30 min; access token 60 days.** Refresh proactively (or re-auth) before expiry; programmatic refresh tokens are partner-gated.
- **`ugcPosts`/`shares`/`v2/assets` are legacy** — build only on `rest/posts` + `rest/images` + `rest/videos`. ([Migration guide](https://learn.microsoft.com/en-us/linkedin/marketing/community-management/community-management-api-migration-guide?view=li-lms-2026-06))

## 10. Testing checklist

- [ ] App created, **Company Page associated and verified** (Settings → Company → Verify).
- [ ] Redirect URL registered (Auth tab) matches your callback exactly.
- [ ] Products added: **Sign In with OIDC** + **Share on LinkedIn** (instant); **Community Management** requested and **approved**.
- [ ] `linkedin.client_id` / `client_secret` in Rails encrypted credentials; `Vendors::Linkedin::Client` reads them.
- [ ] OAuth round-trip: authorize → callback validates `state` → exchange code → `SocialAccount` persisted with encrypted tokens + expiries + granted `scopes`.
- [ ] `/v2/userinfo` returns `sub`; `member_urn = urn:li:person:{sub}` stored.
- [ ] `organizationAcls?q=roleAssignee&role=ADMINISTRATOR` lists the Page(s); `default_org_urn` stored.
- [ ] **Member text post** → `201`, `x-restli-id` captured, visible on profile.
- [ ] **Org text post** → `201`, visible on the Page.
- [ ] **Image post**: initialize → PUT binary → poll AVAILABLE → post with `content.media.id` → `201`.
- [ ] **Video post**: initialize → upload 4 MB parts (capture ETags) → finalize → poll AVAILABLE → post → `201`.
- [ ] **Article post** with manual title/description/thumbnail → `201`.
- [ ] **Edit** (PARTIAL_UPDATE → 204) and **delete** (→ 204) a test post.
- [ ] **Share statistics** (lifetime + 7-day time-bound + per-post) return metrics.
- [ ] **Follower statistics** (lifetime demographics + time-bound gains) return data.
- [ ] Token **refresh / re-auth** path verified before 60-day expiry.
- [ ] `429` handling: exponential backoff + retry in the Sidekiq publish/sync jobs.
- [ ] All four headers present on every `rest/*` call; URNs URL-encoded in GET query strings.

---

## API reference quick table

`{V}` = `LinkedIn-Version` header (e.g. `202606`). All `rest/*` calls also send `Authorization: Bearer`, `LinkedIn-Version: {V}`, `X-Restli-Protocol-Version: 2.0.0`.

| Capability | Method & endpoint | Scope | `Vendors::Linkedin::Actions::*` | `SocialAccount` fields used |
|---|---|---|---|---|
| Authorize (consent) | `GET www.linkedin.com/oauth/v2/authorization` | — (requests scopes) | (controller) | — |
| Exchange code → token | `POST www.linkedin.com/oauth/v2/accessToken` | — | `Operations::…::ExchangeCode` | writes `access_token`, `refresh_token`, expiries, `scopes` |
| Refresh token | `POST www.linkedin.com/oauth/v2/accessToken` (grant_type=refresh_token) | — | `Operations::…::RefreshToken` | `refresh_token` → new `access_token` |
| Member identity | `GET api.linkedin.com/v2/userinfo` | `openid profile email` | `FetchUserInfo` | writes `member_id`,`member_urn`,`member_name`,`member_email` |
| List admin orgs | `GET /rest/organizationAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED` | `rw_organization_admin` / `r_organization_admin` | `FetchAdminOrganizations` | writes `default_org_*` |
| Create post (text/article/reshare) | `POST /rest/posts` | `w_member_social` (person) · `w_organization_social` (org) | `CreatePost` | `access_token`, author URN |
| Init image upload | `POST /rest/images?action=initializeUpload` | same as post | `UploadImage` (step 1) | `access_token`, owner URN |
| Upload image binary | `PUT {uploadUrl}` (image/jpeg) | (signed URL) | `UploadImage` (step 2) | — |
| Init video upload | `POST /rest/videos?action=initializeUpload` | same as post | `UploadVideo` (step 1) | `access_token`, owner URN |
| Upload video parts | `PUT {uploadUrl}` (octet-stream) → capture ETags | (signed URL) | `UploadVideo` (step 2) | — |
| Finalize video | `POST /rest/videos?action=finalizeUpload` | same as post | `UploadVideo` (step 3) | `access_token` |
| Get asset status | `GET /rest/images/{urn}` · `GET /rest/videos/{urn}` | same as post | `GetImage` / `GetVideo` | `access_token` |
| Edit post | `POST /rest/posts/{urn}` + `X-RestLi-Method: PARTIAL_UPDATE` | post scope | `UpdatePost` | `access_token` |
| Delete post | `DELETE /rest/posts/{urn}` + `X-RestLi-Method: DELETE` | post scope | `DeletePost` | `access_token` |
| List posts by author | `GET /rest/posts?q=author&author={urn}` | `r_organization_social` (org) · `r_member_social` (member, restricted) | `ListPosts` | `access_token`, author URN |
| Org share/post stats | `GET /rest/organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity={urn}` | `rw_organization_admin` | `FetchShareStatistics` / `FetchPostStatistics` | `access_token`, org URN |
| Org follower stats | `GET /rest/organizationalEntityFollowerStatistics?q=organizationalEntity&organizationalEntity={urn}` | `rw_organization_admin` | `FetchFollowerStatistics` | `access_token`, org URN |
| Total follower count | `GET /rest/organizations/{id}?…networkSizes…` (Organization Lookup) | `rw_organization_admin` | `FetchNetworkSize` | `access_token`, org URN |

### Primary sources
- Posts API: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/posts-api?view=li-lms-2026-06
- Images API: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/images-api?view=li-lms-2026-06
- Videos API: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/shares/videos-api?view=li-lms-2026-06
- Share Statistics: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/share-statistics?view=li-lms-2026-06
- Follower Statistics: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/follower-statistics?view=li-lms-2026-06
- 3-legged OAuth: https://learn.microsoft.com/en-us/linkedin/shared/authentication/authorization-code-flow
- Refresh tokens: https://learn.microsoft.com/en-us/linkedin/shared/authentication/programmatic-refresh-tokens
- Sign In with OpenID Connect: https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2
- Versioning (LinkedIn-Version): https://learn.microsoft.com/en-us/linkedin/marketing/versioning?view=li-lms-2026-06
- Increasing Access / tiers: https://learn.microsoft.com/en-us/linkedin/marketing/increasing-access?view=li-lms-2025-11
- Organization Access Control by Role: https://learn.microsoft.com/en-us/linkedin/marketing/community-management/organizations/organization-access-control-by-role?view=li-lms-2026-06
- Community Management product: https://developer.linkedin.com/product-catalog/marketing/community-management-api
- Webhook validation: https://learn.microsoft.com/en-us/linkedin/shared/api-guide/webhook-validation
- Rate limits: https://learn.microsoft.com/en-us/linkedin/shared/api-guide/concepts/rate-limits
</content>
</invoke>
