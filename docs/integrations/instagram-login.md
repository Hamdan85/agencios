# Instagram Login Integration — the Page-less, agency-friendly path

> **Why this exists.** The Facebook-Login flow (`meta.md`) requires the client's
> Instagram to be a Business account **linked to a Facebook Page** inside a
> Business Portfolio. Non-technical agency clients can't do that. **Instagram API
> with Instagram Login** lets a client connect by logging in with *only their
> Instagram* — no Facebook Page, no Business Manager. This is the default path the
> Instagram "Conectar" button uses (`SocialPublisher::CONNECT_SLUG["instagram"] =>
> "instagram_login"`). Facebook still uses `meta.md`.

## 0. What the client needs

- An Instagram **Professional** account (Business *or* Creator). Switching is free
  and done in the IG app: Settings → *Account type and tools* → *Switch to
  professional account*. **No Facebook Page required.**

## 1. Meta app setup (one-time, by the agency/platform)

> **The app MUST be type `Business`.** Instagram products/use cases are not
> available to `None`/other app types, and **app type cannot be changed after
> creation** — a `None` app can't be converted, so create a new Business app.
> (A Business *Portfolio* attached to the app is ownership, NOT the app *type*.)

**Create the Business app (App Dashboard → Create app):**

1. **App details** → name + contact email.
2. **Use cases** → in the left filter pick **Content management** (NOT "Others"),
   then check **"Manage messaging and content on Instagram"** (= Instagram API
   with Instagram Login). Also check **"Authenticate … with Facebook Login"** to
   cover Facebook in the same app. → Next.
3. **Business** → attach the Business Portfolio. → finish.

**Configure Instagram Login (App Dashboard → left menu):**

4. Open **"API setup with Instagram login"** (NOT *with Facebook login*) →
   **Add all required permissions**.
5. Copy the **Instagram app ID** + **Instagram app secret** (step 3 *Business
   login settings*) — DIFFERENT from the Facebook `app_id`/`app_secret`. This is
   per Meta's docs, not a quirk of this app.
6. Under *Business login settings → OAuth redirect URIs*, add:
   `https://<APP_HOST>/auth/instagram/callback`
7. Request Advanced Access for the scopes in §3 (App Review + Business
   Verification).

> One Business app powers BOTH networks. The only "two" is the two credential
> pairs inside it (Facebook + Instagram), which Meta requires.

## 2. Credentials

Add to Rails encrypted credentials (`rails credentials:edit`), alongside the
existing `meta:` block:

```yaml
meta:
  app_id:               "..."   # Facebook app id (existing)
  app_secret:           "..."   # Facebook app secret (existing)
  instagram_app_id:     "..."   # NEW — Instagram app id (Instagram Login product)
  instagram_app_secret: "..."   # NEW — Instagram app secret
  graph_version:        "v23.0"
```

ENV fallbacks for dev: `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`.

## 3. Scopes

`Vendors::InstagramLogin::Actions::AuthorizeUrl::SCOPES`:

- `instagram_business_basic` — profile + media read
- `instagram_business_content_publish` — publish posts/reels
- `instagram_business_manage_comments` — read/reply comments
- `instagram_business_manage_insights` — account + media insights

## 4. OAuth flow (all hosts are Instagram, not Facebook)

| Step | Call | Action |
|---|---|---|
| 1. Authorize | `GET https://www.instagram.com/oauth/authorize?client_id={ig_app_id}&redirect_uri=...&response_type=code&scope=...&enable_fb_login=0` | `AuthorizeUrl` |
| 2. Code → short-lived | `POST https://api.instagram.com/oauth/access_token` (form) → `{access_token, user_id}` | `ExchangeCodeForToken` |
| 3. Short → long-lived (~60d) | `GET https://graph.instagram.com/access_token?grant_type=ig_exchange_token&client_secret=...&access_token=...` | `ExchangeLongLivedToken` |
| 4. Profile | `GET https://graph.instagram.com/me?fields=user_id,username,account_type,profile_picture_url` | `GetProfile` |
| Refresh (~day 50) | `GET https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=...` | `RefreshToken` |

`Vendors::InstagramLogin::Actions::ConnectAccount` orchestrates 2–4 and returns
the `SocialAccount` attrs.

## 5. `SocialAccount` mapping

| Column | Value |
|---|---|
| `provider` | `instagram` |
| `connection_type` | `instagram_login` ← discriminates the publish transport |
| `ig_user_id` / `external_user_id` | the IG-scoped `user_id` (publish/insights target) |
| `username` | IG @handle |
| `avatar_url` | `profile_picture_url` |
| `user_access_token` | long-lived IG **user** token (encrypted) — used directly |
| `page_id` / `page_access_token` | **null** (no Facebook Page) |
| `token_expires_at` | now + `expires_in` (~60 days) |

## 6. Publishing, insights & token refresh

Instagram-Login accounts publish via **`graph.instagram.com/{ig_user_id}/media`**
with the **user token**. The endpoints are identical in shape to the Facebook-
Login IG flow, so `Vendors::Meta::Client` simply switches **host** (→
`graph.instagram.com`) and **token** (→ `user_access_token`) when the account is
`connection_type: instagram_login`. The existing `Vendors::Meta::Actions::*` IG
publishing/insights actions then work unchanged:

- **Publish** — `Vendors::Meta::Actions::PublishPost` (single image, carousel,
  Reel-by-URL) → `Publishers::SocialPublisher#publish`.
- **Insights** — `Vendors::Meta::Actions::SyncInsights` (reach/views/likes/…).
- **Permalink** — `GET /{media_id}?fields=permalink`.
- **Token refresh** — `Operations::Social::RefreshToken` routes `instagram_login`
  accounts to `Vendors::InstagramLogin::Actions::RefreshToken`
  (`graph.instagram.com/refresh_access_token`); the existing
  `Social::RefreshTokenJob` sweep already picks them up by `token_expires_at`.

**Not yet wired:** resumable Reel upload for Instagram-Login (the `rupload`
host would need to be `rupload.instagram.com`). The default Reel path uses a
hosted `video_url`, so this only matters if resumable upload is forced.
