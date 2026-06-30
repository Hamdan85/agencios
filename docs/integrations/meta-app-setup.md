# Meta App Setup — the single source of truth (Facebook + Instagram + Threads)

One **Business** Meta app powers all three. This is the step-by-step to configure
it. Per-network API details live in `facebook.md`, `instagram-login.md`,
`threads.md`; THIS file is the dashboard configuration checklist.

> **Key idea.** Three integrations, three independent login flows, three credential
> pairs — all inside ONE Business app:
> - **Facebook** (Pages) → Facebook Login for Business → a **Configuration** (`config_id`)
> - **Instagram** → Instagram Login (own app id/secret) — NO Facebook Page
> - **Threads** → Threads API (own app id/secret)

---

## Step 0 — Create the app (Business type)

App type **cannot** be changed later, and Instagram/Threads need Business type, so
create it fresh if your current app is `None`.

1. https://developers.facebook.com/apps → **Create app**.
2. Use case step → **"Other"** → **Business** (or pick the use cases directly in
   the new flow — see Step 1).
3. Attach your **Business Portfolio** when asked.

## Step 1 — Add the three use cases

App → **Use cases → Add use case**. Add all three (filter by category):

| Use case | Category | Unlocks |
|---|---|---|
| **Manage messaging and content on Instagram** | Content management | Instagram Login + IG permissions |
| **Manage everything on your Page** | (Facebook) | `pages_manage_posts`, `pages_read_user_content`, `read_insights` |
| **Access the Threads API** | (Threads) | Threads Login + permissions |

> ⚠️ **"Manage everything on your Page" is mandatory for Facebook publishing.**
> Without it, `pages_manage_posts` / `pages_read_user_content` / `read_insights`
> are **invalid scopes** and Facebook connect fails (see Troubleshooting).

## Step 2 — Instagram (Instagram Login)

App → **Instagram → API setup with Instagram login → Business login settings**:

- **OAuth redirect URI** → `https://agencios.app/auth/instagram/callback`
- Copy **Instagram app ID** + **secret** → `instagram_app_id` / `instagram_app_secret`
- Permissions (this side): `instagram_business_basic`, `instagram_business_content_publish`,
  `instagram_business_manage_insights`, `instagram_business_manage_replies`

## Step 3 — Facebook (Pages)

**3a. Redirect URI** — App → **Facebook Login for Business → Settings → Valid OAuth
Redirect URIs** → `https://agencios.app/auth/facebook/callback`

**3b. Configuration (config_id)** — App → **Facebook Login for Business →
Configurations → Create configuration**:
- Login variation: **General**
- Access token: **User access token** (Page tokens are derived + auto-refreshed; no
  System User / Business Manager friction for the client)
- Assets: skipped (User access token picks assets at login)
- Permissions — select **exactly these 6** (NOT the `instagram_*` ones):
  `pages_show_list`, `pages_read_engagement`, `pages_manage_posts`,
  `pages_read_user_content`, `read_insights`, `business_management`
- Finish → copy the **Configuration ID** → `fb_login_config_id`

> With `fb_login_config_id` set, the OAuth dialog sends `config_id` (NOT a scope
> list), so the permission set comes from the configuration. Without it, the code
> falls back to the scope list in `Vendors::Meta::Actions::AuthorizeUrl::SCOPES`
> (Facebook Page scopes only).

## Step 4 — Threads

App → **Threads (Access the Threads API)** settings:
- **Redirect URI** → `https://agencios.app/auth/threads/callback`
- Copy **Threads app ID** + **secret** → `threads_app_id` / `threads_app_secret`
- Permissions: `threads_basic`, `threads_content_publish`, `threads_manage_insights`,
  `threads_manage_replies`

## Step 5 — Webhooks (optional)

Connect/publish/insights do NOT need webhooks. Configure only if you want inbound
events (comments, mentions, deauthorization). Each product's Webhooks section asks
for a Callback URL + Verify Token (use the SAME `webhook_verify_token` for all):

| Product | Callback URL |
|---|---|
| Facebook | `https://agencios.app/webhooks/meta` |
| Instagram | `https://agencios.app/webhooks/instagram` |
| Threads | `https://agencios.app/webhooks/threads` |

Verify token field = your `meta.webhook_verify_token` value (same in all three).

---

## Reference — URLs to register

| Network | OAuth callback (redirect URI) | Webhook callback |
|---|---|---|
| Facebook | `https://agencios.app/auth/facebook/callback` | `https://agencios.app/webhooks/meta` |
| Instagram | `https://agencios.app/auth/instagram/callback` | `https://agencios.app/webhooks/instagram` |
| Threads | `https://agencios.app/auth/threads/callback` | `https://agencios.app/webhooks/threads` |

## Reference — credentials (`rails credentials:edit`)

```yaml
meta:
  app_id:               "..."   # Facebook app id
  app_secret:           "..."   # Facebook app secret
  fb_login_config_id:   "..."   # Facebook Login for Business — Configuration ID
  instagram_app_id:     "..."   # Instagram Login
  instagram_app_secret: "..."
  threads_app_id:       "..."   # Threads
  threads_app_secret:   "..."
  webhook_verify_token: "..."   # shared GET-handshake token for all webhooks
  graph_version:        "v25.0" # optional
```

---

## Troubleshooting

**`Invalid Scopes: instagram_manage_insights, pages_manage_posts, pages_read_user_content, read_insights`**
You connected Facebook via the **scope fallback** (no `fb_login_config_id` set yet)
and the app lacks those scopes. Fix:
1. The `instagram_*` scopes were removed from the Facebook flow (they belong to
   Instagram Login) — pull the latest code.
2. Add the **"Manage everything on your Page"** use case → `pages_manage_posts` /
   `pages_read_user_content` / `read_insights` become valid.
3. Best: finish the **Configuration** and set `fb_login_config_id` → the dialog
   then sends `config_id` and **no scope list at all**, so this error can't occur.

**`Nenhuma Página do Facebook encontrada`**
The connecting user manages no Page the app can see. Ensure the user has a Page role
and `pages_show_list` is granted.

**Instagram connects but Facebook doesn't (or vice-versa)**
They're independent flows. Instagram = `instagram_app_id/secret` + Instagram Login.
Facebook = `app_id/secret` + `fb_login_config_id`. Check the right pair is set.

**App in Development mode**
Only people with a **role** on the app (admin/developer/tester) can connect until
the app is Live + permissions pass App Review. Add yourself/testers under App Roles.
