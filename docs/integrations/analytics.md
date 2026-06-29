# Analytics (GTM + Meta Pixel + PostHog)

One consent-gated analytics seam feeds three destinations at once:

| Destination | Loaded by | Purpose |
|---|---|---|
| **Google Tag Manager** | always (Consent Mode v2) | container → GA4 + any tag you configure in GTM |
| **Meta Pixel** | on consent | Meta Ads conversion tracking + optimization |
| **PostHog** | on consent | product analytics, funnels, session replay |

Every page view and conversion event is dispatched **once**, through a single JS
facade, which fans out to all configured destinations. Call sites never branch on
provider and never touch `dataLayer` / `posthog` / `fbq` directly.

## Configuration (ENV — all public client IDs, optional)

These are public identifiers, so they live in `.env`, **not** credentials. Each
tag only loads when its var is present.

```bash
GTM_CONTAINER_ID=GTM-XXXXXXX     # preferred Google container
GA_MEASUREMENT_ID=G-XXXXXXXXXX   # GA4 fallback — only used when no GTM is set
META_PIXEL_ID=000000000000000    # Meta Pixel
POSTHOG_KEY=phc_xxxxxxxxxxxxxxxx # PostHog project API key (public)
POSTHOG_HOST=https://us.i.posthog.com   # defaults to US cloud
```

Restart the server after changing them (they are read at request time into the
shell, but a running Puma caches the ERB output of the consent partial per
deploy). With GA4: configure the GA4 tag **inside GTM** and trigger it on the
`page_view` and conversion events below — that keeps everything under Consent Mode.

## Consent (LGPD)

`app/views/pages/shared/_cookie_consent.html.erb` is the single, framework-agnostic
loader, rendered at the end of `<body>` on all surfaces (marketing, legacy app,
SPA). It:

1. exposes config as `window.__AGENCIOS_ANALYTICS`,
2. sets **Google Consent Mode v2 defaults to `denied`** (ad_storage, ad_user_data,
   ad_personalization, analytics_storage),
3. loads **GTM immediately** (consent-aware, cookieless until granted),
4. **lazy-loads PostHog + the Meta Pixel only after the user accepts**, and
5. broadcasts the choice via `window.__AGENCIOS_CONSENT` + an `agencios:consent`
   CustomEvent so the JS facade flushes its buffer.

Nothing non-essential fires before opt-in. The footer "Preferências de cookies"
re-opens the banner (`window.agenciosOpenCookiePrefs()`).

## The JS facade — `app/frontend/lib/analytics/`

- **`index.js`** — the facade. `page()`, `track()`, `identify()`, `reset()`,
  `setConsent()`, `registerProvider()`. Buffers events until consent **and** a
  provider exist, then flushes. Calls are always safe no-ops otherwise — never
  guard at the call site.
- **`maskPath.js`** — collapses dynamic path segments (`/clientes/abc` →
  `/clientes/:id`) so **record ids never reach a third party**. All page paths go
  through it; keep `ROUTE_PATTERNS` in sync with `App.jsx`.
- **`events.js`** — the canonical event vocabulary (`EVENTS`) + the
  `META_EVENTS` map (funnel events → Meta standard events).
- **`provider.js`** — the fan-out sink: `dataLayer.push` + `posthog.capture` +
  `fbq`. Funnel events use Meta **standard** events; everything else is
  `fbq('trackCustom', …)`.
- **`boot.js`** — `bootAnalytics()`: registers the provider and syncs consent.
  Called once by each entrypoint.

### Wiring

- **SPA** — `entrypoints/application.jsx` calls `bootAnalytics()`;
  `components/shared/AnalyticsBridge.jsx` (mounted at the router root) fires a
  page view on every navigation and `identify` once the user is known.
- **Marketing** — `entrypoints/marketing.js` calls `bootAnalytics()`, fires one
  page view, and tracks any `/cadastro` CTA click as a `cta_click` (→ Meta `Lead`).

## Event taxonomy

Conversion / activation is the priority. Names are snake_case and identical
across all tools.

| Event | Fired from | Meta standard |
|---|---|---|
| `cta_click` | marketing "create account" CTAs | `Lead` |
| `sign_up` | `useRegister` | `CompleteRegistration` |
| `trial_started` | `useRegister` | `StartTrial` |
| `login` / `logout` | `useLogin` / `useLogout` | — |
| `subscribe` | `useBillingMutations.changePlan` | `Subscribe` |
| `checkout_started` | (reserved for Stripe Checkout) | `InitiateCheckout` |
| `creative_generated` | studio `useGenerate` + ticket `generate` | — (also the usage meter) |
| `client_created` / `project_created` / `ticket_created` | their create mutations | — |
| `post_created` / `meeting_scheduled` / `invoice_created` | their mutations | — |
| `member_invited` | `useWorkspaceMutations.invite` | — |
| `ai_action` | ticket `aiAction` | — |

Add an event: add a key to `EVENTS` (and to `META_EVENTS` if Meta Ads should
optimize toward it), then `analytics.track(EVENTS.X, props)` at the call site.
Keep props free of PII and raw record ids (they fan out to third parties);
`identify` is the only place a user id is sent, and only PostHog receives traits.

## Server-side / future

Client pixels miss ad-blocked + post-redirect conversions. When revenue
attribution matters, add **Stripe-webhook-driven** server events: Meta Conversions
API (`Purchase`) and a PostHog server capture, keyed on the Stripe event id for
idempotency. Out of scope here — the client layer is "prepared for Meta Ads".
