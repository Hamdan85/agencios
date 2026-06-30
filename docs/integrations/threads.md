# Threads Integration — the Page-less, agency-friendly path

> Threads (Meta) mirrors **Instagram Login**: the client logs in with their own
> **Threads** account — no Facebook Page, no Business Manager. The Threads
> "Conectar" button uses `SocialPublisher::CONNECT_SLUG["threads"] => "threads"`
> → `Vendors::Threads`. Tokens are Threads **user** tokens used directly against
> `graph.threads.net`.

## 0. What the client needs

- A Threads account (it's created from their Instagram). No Facebook Page.

## 1. Meta app setup (one-time)

In the **same Business app** (App Dashboard → Use cases → Add use case):

1. Add **"Access the Threads API"** (a.k.a. *Threads API* use case).
2. Open the Threads API settings → copy the **Threads app ID** + **Threads app
   secret** (separate from Facebook/Instagram credentials).
3. Add the OAuth redirect URI: `https://<APP_HOST>/auth/threads/callback`.
4. Request Advanced Access for the scopes in §3 (App Review).

## 2. Credentials

```yaml
meta:
  threads_app_id:     "..."   # NEW — from the Threads API use case
  threads_app_secret: "..."   # NEW
```

ENV fallbacks: `THREADS_APP_ID`, `THREADS_APP_SECRET`.

## 3. Scopes

`Vendors::Threads::Actions::AuthorizeUrl::SCOPES`:

- `threads_basic` — profile + media read
- `threads_content_publish` — publish posts
- `threads_manage_insights` — media/account insights
- `threads_manage_replies` — read/reply to replies

## 4. OAuth flow (all hosts are Threads)

| Step | Call | Action |
|---|---|---|
| 1. Authorize | `GET https://threads.net/oauth/authorize?client_id={threads_app_id}&redirect_uri=...&response_type=code&scope=...` | `AuthorizeUrl` |
| 2. Code → short-lived | `POST https://graph.threads.net/oauth/access_token` (form) → `{access_token, user_id}` | `ExchangeCodeForToken` |
| 3. Short → long-lived (~60d) | `GET https://graph.threads.net/access_token?grant_type=th_exchange_token&client_secret=...&access_token=...` | `ExchangeLongLivedToken` |
| 4. Profile | `GET https://graph.threads.net/v1.0/me?fields=id,username,threads_profile_picture_url` | `GetProfile` |
| Refresh (~day 50) | `GET https://graph.threads.net/refresh_access_token?grant_type=th_refresh_token&access_token=...` | `RefreshToken` |

> The OAuth endpoints (`/oauth/access_token`, `/access_token`,
> `/refresh_access_token`) are **unversioned**; data calls (`/me`, publish,
> insights) use the **`/v1.0/`** versioned base.

## 5. `SocialAccount` mapping

| Column | Value |
|---|---|
| `provider` | `threads` |
| `external_user_id` | Threads user id (publish/insights target) |
| `username` | Threads @handle |
| `avatar_url` | `threads_profile_picture_url` |
| `user_access_token` | long-lived Threads user token (encrypted) |
| `page_id` / `page_access_token` | null |
| `token_expires_at` | now + `expires_in` (~60 days) |

## 6. Publishing

`Vendors::Threads::Actions::PublishPost` (via `Publishers::SocialPublisher#publish`):

1. Create container — `POST /{user-id}/threads` with `media_type`:
   - `TEXT` (`text`), `IMAGE` (`image_url`+`text`), `VIDEO` (`video_url`+`text`),
     or `CAROUSEL` (`children=` of `is_carousel_item` containers).
2. For VIDEO/CAROUSEL, poll `GET /{creation_id}?fields=status` until `FINISHED`.
3. Publish — `POST /{user-id}/threads_publish?creation_id=...` → media id.
4. Permalink — `GET /{media-id}?fields=permalink`.

## 7. Insights

`Vendors::Threads::Actions::SyncInsights` — `GET /{media-id}/insights?metric=
views,likes,replies,reposts,quotes,shares`, normalized to the shared shape
(`replies→comments`, `reposts+quotes+shares→shares`, no `saves`).

## 8. Token refresh

`Operations::Social::RefreshToken` resolves `threads` → `Vendors::Threads` →
`RefreshToken` (`graph.threads.net/refresh_access_token`); the existing
`Social::RefreshTokenJob` sweep picks Threads accounts up by `token_expires_at`.
