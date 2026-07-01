# X (Twitter) API v2 — Posting, Media Upload & Metrics (for `agencios`)

> Researched against official X docs (`docs.x.com` / `developer.x.com`) and current pricing reporting, 2025–2026. Cited inline. **Pricing and tier availability on X change frequently and aggressively — re-verify before committing budget.**

---

## 0. What you'll build

A direct X integration for `agencios` so a workspace can connect an X account (OAuth 2.0 PKCE), publish text/image/video posts and threads, and read back engagement metrics.

Concrete pieces:

- **OAuth 2.0 Authorization Code + PKCE** connect flow → stores tokens on a `SocialAccount` (`provider: :x`).
- **Media upload** via the v2 chunked endpoint (`INIT → APPEND → FINALIZE → STATUS`) — this replaced the old v1.1 `media/upload`.
- **Post creation** via `POST /2/tweets` (text, media, reply, quote, threads).
- **Metrics** via `GET /2/tweets` with `tweet.fields=public_metrics` (and owner-only `non_public_metrics`/`organic_metrics` for posts < 30 days old).

Mapped to the house conventions:

| Concern | Class |
|---|---|
| Build authorize URL | `Vendors::X::Actions::BuildAuthorizeUrl` |
| Exchange code → tokens | `Vendors::X::Actions::ExchangeCode` |
| Refresh token | `Vendors::X::Actions::RefreshToken` |
| Low-level HTTP | `Vendors::X::Client` |
| Upload media (chunked) | `Vendors::X::Actions::UploadMedia` |
| Create a post | `Vendors::X::Actions::CreatePost` |
| Read metrics | `Vendors::X::Actions::FetchMetrics` |
| Orchestration (multi-step publish) | `Operations::Publishing::PublishToX` |
| Background dispatch | `PublishToXJob` (Sidekiq) |

---

## 1. Accounts & prerequisites — and a BLUNT note on pricing tiers

### Prerequisites
1. An X account (preferably the brand/agency account, or — for white-label — each client connects their own).
2. A **developer account** at the X developer portal (`developer.x.com`).
3. A **Project**, and an **App inside that Project**. The v2 endpoints only work for apps attached to a Project. Standalone apps get nothing useful. ([rate-limits docs](https://docs.x.com/x-api/fundamentals/rate-limits))

### BLUNT note on tiers — what's realistically possible

X gutted free/cheap API access in 2023 and has kept tightening since. The reality as of 2025–2026:

| Tier | Price | Write (posts) | Read | Verdict |
|---|---|---|---|---|
| **Free** | $0 | **500 posts/month** (app+user combined), ~17 requests/24h on write endpoints | **Essentially none** — write-only; reads are heavily gated/blocked | Demo/testing only. Cannot read metrics. |
| **Basic** | **$200/mo** (was $100) | ~50,000 posts/month | ~15,000 reads/month | Hobby/small. **Closed to new signups** as of 2026. |
| **Pro** | **$5,000/mo** | high | ~1,000,000 reads/month | Serious commercial. **Closed to new signups** as of 2026. |
| **Enterprise** | **$42,000+/mo** + ~$1/mo per connected account | custom | custom | Out of reach for most. |
| **Pay-as-you-go** (new, GA'd Feb 6 2026) | usage-based | ~**$0.015 per post**, ~**$0.20 per post containing a link** | metered, capped ~2M reads/mo | The realistic option for new builds. |

Sources: [wearefounders.uk — X API price hike](https://www.wearefounders.uk/the-x-api-price-hike-a-blow-to-indie-hackers/), [twitterapi.io pricing 2025](https://twitterapi.io/blog/twitter-api-pricing-2025), [xpoz.ai tiers](https://www.xpoz.ai/blog/guides/understanding-twitter-api-pricing-tiers-and-alternatives/), [postproxy X API pricing 2026](https://postproxy.dev/blog/x-api-pricing-2026/).

**The honest takeaways for `agencios`:**

- **Free tier is a trap for production.** 500 posts/month total and (critically) **no read access** means you cannot fetch `public_metrics`. You can post on Free, you cannot do analytics on Free.
- **Basic ($200/mo) and Pro ($5,000/mo) are now legacy** — only existing subscribers keep them. New developers get **pay-as-you-go or Enterprise**. ([blotato](https://www.blotato.com/blog/twitter-api-pricing), [postproxy](https://postproxy.dev/blog/x-api-pricing-2026/))
- **Posts with links cost ~13× more** under pay-as-you-go (~$0.20 vs ~$0.015). For an agency that posts campaign links constantly, this adds up fast — factor it into per-workspace billing.
- If reading metrics at scale is the real product, the direct X path is expensive. Factor X's read/analytics pricing into per-workspace billing, and gate analytics features on the account's X tier.

---

## 2. Create the app (clickpath)

1. Go to **`developer.x.com`** → sign in → **Developer Portal**.
2. **Projects & Apps** → **Add Project** (give it a name, use-case, description).
3. Inside the project, **Add App** (or use the auto-created one). Save the **API Key/Secret** and (for confidential clients) the **Client ID / Client Secret** shown once.
4. Open the app → **User authentication settings** → **Set up / Edit**.
5. Configure:
   - **App permissions:** *Read and write* (and *Direct Messages* only if needed). Write is required to post.
   - **Type of App:** *Web App, Automated App or Bot* → **Confidential client** (server-side Rails = confidential; you get a Client Secret and use it). Choose *Native/SPA* only for public clients with no secret.
   - **Callback URI / Redirect URL:** must be an **exact match** of what you send in the OAuth request, e.g. `https://app.agencios.com/oauth/x/callback` (and `http://127.0.0.1:3000/oauth/x/callback` for local dev — `localhost` literal can be finicky; prefer `127.0.0.1`).
   - **Website URL.**
6. Save. The portal now exposes **OAuth 2.0 Client ID and Client Secret** — these drive the PKCE flow below.

---

## 3. Scopes

Request the minimum needed. Space-separated in the authorize URL. Full list at [oauth2 authorization-code docs](https://docs.x.com/resources/fundamentals/authentication/oauth-2-0/authorization-code).

| Scope | Why |
|---|---|
| `tweet.read` | Read posts / required alongside most actions and to read metrics |
| `tweet.write` | **Create posts** (`POST /2/tweets`) |
| `users.read` | Read the authenticated user's profile (to store handle/id on `SocialAccount`) |
| `media.write` | **Upload media** via the v2 chunked endpoint (required for image/video posts) |
| `offline.access` | **Get a refresh token** — without this, access tokens die in 2h and you must re-auth |

So the typical `agencios` scope string:

```
tweet.read tweet.write users.read media.write offline.access
```

Notes:
- `media.write` is comparatively new and is the scope that authorizes the **v2** media upload endpoint. ([chunked upload docs](https://docs.x.com/x-api/media/quickstart/media-upload-chunked))
- Add `dm.read`/`dm.write` only if you build DMs; add `like.read`/`follows.read` etc. only as features demand.

---

## 4. OAuth 2.0 PKCE flow — exact endpoints, params, refresh

Reference: [Authorization Code with PKCE](https://docs.x.com/resources/fundamentals/authentication/oauth-2-0/authorization-code).

### Step A — generate PKCE pair (server side, per attempt)
- `code_verifier` = random high-entropy string (43–128 chars).
- `code_challenge` = BASE64URL(SHA256(code_verifier)) with `code_challenge_method=S256`.
- `state` = random string (≤ 500 chars), persisted (session/Redis) for CSRF check.

Store `code_verifier` + `state` keyed to the workspace until callback. → `Vendors::X::Actions::BuildAuthorizeUrl`

### Step B — redirect the user to the authorize endpoint

```
GET https://x.com/i/oauth2/authorize
  ?response_type=code
  &client_id=<CLIENT_ID>
  &redirect_uri=https://app.agencios.com/oauth/x/callback
  &scope=tweet.read%20tweet.write%20users.read%20media.write%20offline.access
  &state=<STATE>
  &code_challenge=<CODE_CHALLENGE>
  &code_challenge_method=S256
```

User approves → X redirects back to `redirect_uri?code=<AUTH_CODE>&state=<STATE>`. Verify `state` matches. The `code` is short-lived (~30s) — exchange immediately.

### Step C — exchange code for tokens

```
POST https://api.x.com/2/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&code=<AUTH_CODE>
&client_id=<CLIENT_ID>
&redirect_uri=https://app.agencios.com/oauth/x/callback
&code_verifier=<CODE_VERIFIER>
```

- **Confidential client (our Rails server):** send HTTP **Basic auth header** = `Authorization: Basic base64(client_id:client_secret)`. (Public clients omit this and rely on PKCE only.)

Response:
```json
{
  "token_type": "bearer",
  "expires_in": 7200,
  "access_token": "...",
  "scope": "tweet.read tweet.write users.read media.write offline.access",
  "refresh_token": "..."   // present only if offline.access was requested
}
```
→ `Vendors::X::Actions::ExchangeCode`. Access token valid **2 hours**.

### Step D — refresh

```
POST https://api.x.com/2/oauth2/token
Content-Type: application/x-www-form-urlencoded
Authorization: Basic base64(client_id:client_secret)   # confidential client

grant_type=refresh_token
&refresh_token=<REFRESH_TOKEN>
&client_id=<CLIENT_ID>
```

Returns a new `access_token` **and a new `refresh_token`** (rotating — persist the new one each time). → `Vendors::X::Actions::RefreshToken`.

**Implementation rule for `agencios`:** wrap every authed call so that on a 401 it refreshes once via `RefreshToken`, persists the rotated tokens to the `SocialAccount`, and retries. Don't proactively refresh on every call; refresh lazily on expiry/401.

---

## 5. Store credentials (Rails credentials + `SocialAccount` columns)

### App-level secrets → Rails encrypted credentials

```yaml
# rails credentials:edit
x:
  client_id: "..."
  client_secret: "..."
  # api_key / api_secret only if you also need OAuth 1.0a (e.g. certain owner-only metrics fallbacks)
```

Read via `Rails.application.credentials.dig(:x, :client_id)`. Never in `.env`.

### Per-account tokens → `SocialAccount` model

`SocialAccount belongs_to :workspace`, with **encrypted** token columns (`encrypts :access_token` etc.):

```ruby
# migration sketch
create_table :social_accounts do |t|
  t.references :workspace, null: false, foreign_key: true
  t.string  :provider, null: false            # "x", "threads", ...
  t.string  :external_account_id              # X user id
  t.string  :username                         # @handle
  t.text    :access_token                     # encrypted
  t.text    :refresh_token                    # encrypted
  t.datetime :token_expires_at
  t.string  :scopes
  t.jsonb   :metadata, default: {}
  t.timestamps
end
add_index :social_accounts, [:workspace_id, :provider, :external_account_id], unique: true
```

```ruby
class SocialAccount < ApplicationRecord
  belongs_to :workspace
  encrypts :access_token
  encrypts :refresh_token
  enum :provider, { x: "x", threads: "threads" }, prefix: true
end
```

`token_expires_at = Time.current + expires_in.seconds` on exchange/refresh.

---

## 6. Publishing flow — chunked media upload + `POST /2/tweets` + threads

### 6a. Media upload (v2 chunked — replaces v1.1)

Base: `https://api.x.com/2/media/upload`. Auth: `Authorization: Bearer <USER_ACCESS_TOKEN>` (scope `media.write`). Reference: [Chunked Media Upload](https://docs.x.com/x-api/media/quickstart/media-upload-chunked).

**INIT**
```
POST https://api.x.com/2/media/upload   (command=INIT)
  media_type=video/mp4
  total_bytes=<size_in_bytes>
  media_category=tweet_video      # tweet_image | tweet_gif | tweet_video | amplify_video
```
Returns `media_id`, `media_key`, `expires_after_secs`.

**APPEND** (one call per chunk; example chunk size ~1 MB, keep segments small/<5 MB)
```
POST https://api.x.com/2/media/upload   (command=APPEND)
  media_id=<media_id>
  segment_index=0                 # zero-indexed, increment per chunk
  media=<binary chunk>            # multipart
```

**FINALIZE**
```
POST https://api.x.com/2/media/upload   (command=FINALIZE)
  media_id=<media_id>
```
If the response includes a `processing_info` block (videos & GIFs), the asset is still transcoding.

**STATUS** (poll only if `processing_info` present)
```
GET https://api.x.com/2/media/upload?command=STATUS&media_id=<media_id>
```
States: `pending → in_progress → succeeded | failed`. Respect `check_after_secs` between polls. Only attach the `media_id` to a post once `succeeded`.

`media_category` cheat sheet: `tweet_image`, `tweet_gif`, `tweet_video`, `amplify_video`.

→ `Vendors::X::Actions::UploadMedia` returns the final `media_id`. Images can skip STATUS polling; videos/GIFs must poll.

### 6b. Create the post — `POST /2/tweets`

Auth: Bearer user token, scope `tweet.write`. Reference: [Creation of a Post](https://docs.x.com/x-api/posts/creation-of-a-post). Returns **201** with `{ "data": { "id", "text" } }`.

Body fields:
| Field | Notes |
|---|---|
| `text` | post body |
| `media.media_ids` | array of uploaded `media_id`s; optional `media.tagged_user_ids` |
| `reply.in_reply_to_tweet_id` | makes it a reply / thread continuation |
| `quote_tweet_id` | quote post (**Enterprise-gated** per docs) |
| `poll` | `{ "options": [...], "duration_minutes": N }` |
| `reply_settings` | `following` \| `mentionedUsers` \| `subscribers` \| `verified` |
| `for_super_followers_only` | boolean |

Examples:
```json
// text only
{ "text": "Hello from agencios" }

// with media
{ "text": "Launch day", "media": { "media_ids": ["1146654567674912769"] } }

// reply
{ "text": "follow-up", "reply": { "in_reply_to_tweet_id": "1346889436626259968" } }

// quote (Enterprise only)
{ "text": "worth a read", "quote_tweet_id": "1346889436626259968" }
```

→ `Vendors::X::Actions::CreatePost`.

### 6c. Threads

A thread is just sequential replies. Post tweet #1, capture its `id`, then post tweet #2 with `reply.in_reply_to_tweet_id` = #1's id, #3 replying to #2, etc. Orchestrate in `Operations::Publishing::PublishToX` (upload all media first, then chain the posts; persist each returned id so a retry doesn't double-post). Run under `PublishToXJob`. Watch the per-window post rate limit between calls.

---

## 7. Analytics flow — `public_metrics` & tweet lookup, with tier gating

Reference: [Metrics](https://docs.x.com/x-api/fundamentals/metrics).

Endpoints: `GET /2/tweets/:id` (single) or `GET /2/tweets?ids=...` (batch), with the metrics requested via `tweet.fields`.

```
GET https://api.x.com/2/tweets/:id?tweet.fields=public_metrics
GET https://api.x.com/2/tweets?ids=ID1,ID2&tweet.fields=public_metrics
```

Metric groups:
| Field group | Contents | Auth | Constraints |
|---|---|---|---|
| `public_metrics` | `retweet_count`, `reply_count`, `like_count`, `quote_count`, `impression_count`, `bookmark_count` | App Bearer or user token — any public post | The bread-and-butter for `agencios` |
| `non_public_metrics` | `url_link_clicks`, `user_profile_clicks`, `engagements` | **User context, owner-only** | **Posts < 30 days old only** |
| `organic_metrics` | organic (non-promoted) breakdown | User context, owner-only | Posts < 30 days old |
| `promoted_metrics` | ad-promoted breakdown | User context, owner-only | Posts < 30 days old |

→ `Vendors::X::Actions::FetchMetrics`. Cache results; refresh on a schedule (Sidekiq), don't poll hot.

### Tier gating — the catch
- Reading metrics requires **read access**, which the **Free tier does not give** in practice (Free is write-only). So on Free you can post but get **zero analytics**. ([metrics docs](https://docs.x.com/x-api/fundamentals/metrics), pricing sources above)
- `non_public_metrics`/`organic_metrics` need user-context auth (the OAuth 2.0 user token you already store) **and** only work for the connected account's own posts within 30 days. Build a "metrics snapshot within 30 days" cron, or you lose the owner-only numbers permanently.
- For competitor/3rd-party post metrics you only ever get `public_metrics`.

---

## 8. Webhooks — Account Activity API (note)

X's realtime push is the **Account Activity API (AAA)** — subscribe to a user's activity (post create/delete, favorite, follow/unfollow, mute, DMs incl. typing/read receipts) delivered to your webhook. ([AAA enterprise reference](https://developer.x.com/en/docs/x-api/enterprise/account-activity-api/api-reference), [managing webhooks](https://developer.twitter.com/en/docs/twitter-api/enterprise/account-activity-api/guides/managing-webhooks-and-subscriptions)).

Reality for `agencios`:
- AAA is **Enterprise (and legacy Premium)** — not part of Free/Basic/Pro/pay-as-you-go. Expensive and gated.
- A clean **v2 replacement is still "under consideration"** — no GA, no commitment. ([devcommunity](https://devcommunity.x.com/t/plan-changes-v2-and-account-activity-api/190696))
- It uses a **CRC challenge** webhook handshake (X periodically POSTs a `crc_token`; you must reply with an HMAC-SHA256 of it using your consumer secret).

**Recommendation:** do **not** build on AAA for v1 of `agencios`. Use **polling** (`Vendors::X::Actions::FetchMetrics` on a Sidekiq schedule) for engagement updates. Revisit only if a paying need for realtime mentions/DMs appears and the budget justifies Enterprise.

---

## 9. Rate limits & gotchas

- **Tier caps dominate.** Free ≈ 500 posts/month + ~17 write requests/24h, no reads. Legacy Basic/Pro use 15-min windows; Free uses harsh 24-h windows. ([rate-limits docs](https://docs.x.com/x-api/fundamentals/rate-limits), [devcommunity free-tier limits](https://devcommunity.x.com/t/specifics-about-the-new-free-tier-rate-limits/229761))
- **Pay-as-you-go cost:** ~$0.015/post, **~$0.20/post with a link**. Agencies post links → budget accordingly. Reads metered, ~2M/mo cap. ([postproxy](https://postproxy.dev/blog/x-api-pricing-2026/), [blotato](https://www.blotato.com/blog/twitter-api-pricing))
- **Always honor response headers** `x-rate-limit-remaining` / `x-rate-limit-reset`; back off and queue, never hammer.
- **Access token = 2h.** Without `offline.access` you have no refresh token and the connection silently dies. Always request `offline.access`.
- **Refresh tokens rotate** — persist the new one returned on every refresh or you'll lock the account out.
- **`media.write` scope is mandatory** for the v2 upload endpoint; missing it → 403 on INIT.
- **Video must finish processing** (STATUS=`succeeded`) before `POST /2/tweets`, else the post fails.
- **`redirect_uri` must match byte-for-byte** what's registered in the portal.
- **Quote tweets are Enterprise-gated** in the docs — don't promise quote-posting on cheap tiers.
- **Auth code expires ~30s** — exchange synchronously in the callback.
- Re-verify tiers/prices before launch; X changes them with little notice.

---

## 10. Testing checklist

- [ ] App created **inside a Project**; OAuth 2.0 Client ID/Secret captured.
- [ ] Callback URI registered matches `redirect_uri` exactly (use `127.0.0.1` locally).
- [ ] Full PKCE round-trip: authorize → callback → `state` verified → `ExchangeCode` returns access + refresh token.
- [ ] Tokens encrypted on `SocialAccount`; `token_expires_at` set.
- [ ] `RefreshToken` works near expiry and **persists the rotated refresh token**; 401-retry wrapper confirmed.
- [ ] Image post: `UploadMedia` (`tweet_image`, no STATUS poll) → `CreatePost` with `media_ids` → 201.
- [ ] Video post: INIT/APPEND/FINALIZE → STATUS polled to `succeeded` → posted.
- [ ] Text-only post returns 201 with an `id`.
- [ ] Thread: 3 chained replies, ids persisted, no double-post on retry.
- [ ] `FetchMetrics` returns `public_metrics`; owner-only `non_public_metrics` works for a <30-day-old own post (on a read-capable tier).
- [ ] Rate-limit headers respected; graceful backoff/queue.
- [ ] Confirmed the **billing tier actually allows reads** before shipping analytics.

---

## API reference quick table

| Purpose | Method & Endpoint | Auth / Scope | Action class |
|---|---|---|---|
| Authorize (redirect) | `GET https://x.com/i/oauth2/authorize` | PKCE params | `Actions::BuildAuthorizeUrl` |
| Token exchange | `POST https://api.x.com/2/oauth2/token` (`grant_type=authorization_code`) | Basic auth (confidential) | `Actions::ExchangeCode` |
| Refresh | `POST https://api.x.com/2/oauth2/token` (`grant_type=refresh_token`) | Basic auth; `offline.access` | `Actions::RefreshToken` |
| Media INIT | `POST https://api.x.com/2/media/upload` (`command=INIT`) | Bearer / `media.write` | `Actions::UploadMedia` |
| Media APPEND | `POST .../2/media/upload` (`command=APPEND`) | Bearer / `media.write` | `Actions::UploadMedia` |
| Media FINALIZE | `POST .../2/media/upload` (`command=FINALIZE`) | Bearer / `media.write` | `Actions::UploadMedia` |
| Media STATUS | `GET .../2/media/upload?command=STATUS&media_id=` | Bearer / `media.write` | `Actions::UploadMedia` |
| Create post | `POST https://api.x.com/2/tweets` | Bearer / `tweet.write` | `Actions::CreatePost` |
| Metrics (single) | `GET https://api.x.com/2/tweets/:id?tweet.fields=public_metrics` | Bearer / `tweet.read` (read tier) | `Actions::FetchMetrics` |
| Metrics (batch) | `GET https://api.x.com/2/tweets?ids=...&tweet.fields=public_metrics` | Bearer / `tweet.read` | `Actions::FetchMetrics` |

**Doc sources:** [chunked media upload](https://docs.x.com/x-api/media/quickstart/media-upload-chunked) · [create a post](https://docs.x.com/x-api/posts/creation-of-a-post) · [OAuth 2.0 PKCE](https://docs.x.com/resources/fundamentals/authentication/oauth-2-0/authorization-code) · [metrics](https://docs.x.com/x-api/fundamentals/metrics) · [rate limits](https://docs.x.com/x-api/fundamentals/rate-limits) · [Account Activity API](https://developer.x.com/en/docs/x-api/enterprise/account-activity-api/api-reference)
