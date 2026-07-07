# agencios — Integration Playbooks

This folder contains **step-by-step playbooks**, one per external platform, for standing up each
integration end-to-end: the developer-portal clickpath (create app, scopes, OAuth) **plus** the
agencios backend plan (vendor classes, `SocialAccount`/model columns, operations, jobs, webhooks).

> **How to use these.** Each guide is written to be executed by an agent. Paste a guide into the
> **Claude Chrome extension** to have it drive the browser through the portal setup, then implement
> the "Backend plan" section in this repo against agencios conventions
> ([`../../CLAUDE.md`](../../CLAUDE.md), [`../ARCHITECTURE.md`](../ARCHITECTURE.md)). Every guide
> maps each API call to a concrete `Vendors::<Vendor>::Actions::*` class and the `SocialAccount`
> columns it reads — follow them literally.
>
> Currency of the research is noted at the top of each file (verified 2025–2026). **APIs change** —
> re-verify versions, scopes, and pricing in the portal before committing code or budget.

## Index

### Social networks — publishing & analytics

| Guide | Platform | Notes |
|---|---|---|
| [meta.md](./meta.md) | Instagram + Facebook (Meta Graph) | **One guide, one app.** Reels/carousel/image for IG; page posts/video/Reels for FB; shared OAuth, `SocialAccount`, webhook endpoint |
| [tiktok.md](./tiktok.md) | TikTok | Content Posting API; audit required before public posts |
| [linkedin.md](./linkedin.md) | LinkedIn | Posts API; org posting/analytics need partner approval |
| [x-twitter.md](./x-twitter.md) | X (Twitter) | v2 API; **Free is write-only, no analytics** |
| Threads | Threads (Meta) | Threads API; text + image/video posts, post insights |

### Creative generation + Google integrations

| Guide | Platform | Sections |
|---|---|---|
| [google.md](./google.md) | **All Google surfaces** | §3 Sign-In with Google · §4 Calendar + Meet · §5 YouTube (Data API v3 + Analytics) · §6 **Google Banana** (Imagen 3 image generation) |

> **Video generation** has no per-vendor portal guide: it runs through the OpenRouter API
> (`Vendors::OpenRouter` — text models + video render jobs, engines configured per mode in
> `VideoConfig` from `/admin`), with **Cartesia** for voice, **Jamendo/Epidemic Sound** for music
> (`Vendors::Music`) and FFmpeg for compose. Keys live in credentials (`openrouter.api_key`,
> `cartesia.api_key`, …) — see [`../CREDENTIALS.md`](../CREDENTIALS.md). The legacy HeyGen
> integration was removed (2026-07); [heygen.md](./heygen.md) is historical.

### Billing

| Guide | Platform | Notes |
|---|---|---|
| [stripe-billing.md](./stripe-billing.md) | Stripe | SaaS billing: plan tiers + credit-pack checkout (usage = prepaid credits, see [`../pricing-model.md`](../pricing-model.md)) |
| [mercado-pago.md](./mercado-pago.md) | Mercado Pago | Client billing: Pix-first, boleto, card, webhooks |

---

## Strategy: direct integration

agencios publishes through one seam — `Publishers::SocialPublisher` — and every network is served by
its own **direct** vendor (`Vendors::Meta`, `Vendors::Threads`, `Vendors::TikTok`, …). Callers never
branch on provider; the publisher resolves the vendor per network.

**Direct, always.** Each network is built against its own app/API. You get full control of the
publishing payload, deeper and cheaper analytics, no per-post markup, and no third-party dependency
in the critical path. There is **no aggregator** in the stack.

### Recommended rollout

1. **Meta first** — Instagram + Facebook share one app and OAuth; highest-value networks.
2. **Threads** — Meta-owned; reuses much of the Meta app setup.
3. **YouTube** — straightforward OAuth, but watch the upload quota.
4. **TikTok, LinkedIn, X** — each has a real approval gate (TikTok audit / LinkedIn partner approval
   / X paid analytics); plan for the review lead time when scheduling the work.

### Effort & gating at a glance

| Network | Direct approval gate | Analytics depth |
|---|---|---|
| Instagram / Facebook | App Review + Business Verification | High |
| Threads | Meta app review (shared with Meta) | Medium |
| YouTube | Sensitive-scope verification (~days–weeks) | High |
| TikTok | **App audit** (public posts blocked until done) | Medium |
| LinkedIn | **Partner approval** for org posting/analytics | Medium (org only) |
| X (Twitter) | Paid tier for any read/analytics | Low on Free |

---

## Shared backend conventions (all guides assume these)

- **Vendors** live under `app/services/vendors/<Vendor>/` as a `Client` + `Actions::<Verb>` classes
  (`.call`-style). All external knowledge stays here.
- **OAuth tokens & account ids** live on the `SocialAccount` model (`belongs_to :workspace`), with
  **encrypted** token columns. Provider-specific columns are listed in each guide; add them as
  migrations. Exception: Google Calendar/Sign-In tokens live on the **`User`** model.
- **App-level secrets** (app id/secret, API keys, webhook secrets) live in **Rails encrypted
  credentials**, namespaced per vendor (`credentials.meta`, `credentials.google`,
  `credentials.google_banana`, …). See [`../CREDENTIALS.md`](../CREDENTIALS.md).
- **Side effects** (publishing, token refresh, metric sync, generation finalization) live in
  `Operations::*` and run on **Sidekiq**; webhooks are handled by `Controllers::Webhooks::*` →
  `Operations::*` and always verify signatures.
- **Publishing** always goes through `Publishers::SocialPublisher`; **never** call a network vendor
  directly from an operation that should be provider-agnostic.

See [`../SPECIFICATION.md`](../SPECIFICATION.md) §6 (social), §5 (creatives), §8–§9 (billing) for
how these vendors slot into the data model and pipelines.
