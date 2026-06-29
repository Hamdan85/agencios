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
| [instagram.md](./instagram.md) | Instagram (Meta Graph) | Reels/carousel/image; one Meta app shared with Facebook |
| [facebook.md](./facebook.md) | Facebook Pages (Meta Graph) | Page posts, video, Reels; same Meta app |
| [tiktok.md](./tiktok.md) | TikTok | Content Posting API; audit required before public posts |
| [youtube.md](./youtube.md) | YouTube (Data API v3) | Resumable upload, Shorts; quota-sensitive |
| [linkedin.md](./linkedin.md) | LinkedIn | Posts API; org posting/analytics need partner approval |
| [x-twitter.md](./x-twitter.md) | X (Twitter) | v2 API; **Free is write-only, no analytics** |
| [upload-post.md](./upload-post.md) | Upload-Post (aggregator) | One API → many networks; the fast-path fallback |

### Creative generation
| Guide | Platform | Notes |
|---|---|---|
| [heygen.md](./heygen.md) | HeyGen | UGC / avatar talking-head video; metered (`video_generation`) |

> HyperFrames (the other video engine) and the image/carousel model are documented inline in
> [`../SPECIFICATION.md`](../SPECIFICATION.md) §5; add dedicated guides here when those vendors are
> finalized.

### Billing
| Guide | Platform | Notes |
|---|---|---|
| [stripe-billing.md](./stripe-billing.md) | Stripe | SaaS billing: plan tiers + usage meters (carousel/video) |
| [mercado-pago.md](./mercado-pago.md) | Mercado Pago | Client billing: Pix-first, boleto, card, webhooks |

---

## Strategy: direct integration vs. aggregator

agencios publishes through one seam — `Publishers::SocialPublisher` — so any network can be served
either by a **direct** vendor (`Vendors::Meta`, `Vendors::TikTok`, …) or by the **aggregator**
(`Vendors::UploadPost`). Switching a network is a one-line change in the publisher; callers never
branch on provider.

**Default: direct.** Prefer building the network's own app/API. You get full control of the
publishing payload, deeper and cheaper analytics, no per-post markup, and no third-party dependency
in the critical path.

**Aggregator (Upload-Post) when:** you need to ship a long-tail network *now*, the network's app
review is slow or gated (TikTok audit, LinkedIn partner approval, X paid tiers), or analytics depth
doesn't matter for that network yet. Trade-offs: per-upload cost, a dependency, shallower analytics,
and ToS exposure. See [upload-post.md](./upload-post.md).

### Recommended rollout
1. **Meta first (direct)** — Instagram + Facebook share one app and OAuth; highest-value networks.
2. **YouTube (direct)** — straightforward OAuth, but watch the upload quota.
3. **TikTok, LinkedIn, X** — start via **Upload-Post** to ship, because each has a real gate
   (TikTok audit / LinkedIn partner approval / X paid analytics). Migrate to direct per network as
   approvals land and analytics needs grow.

### Effort & gating at a glance
| Network | Direct approval gate | Analytics depth (direct) | Aggregator-friendly |
|---|---|---|---|
| Instagram / Facebook | App Review + Business Verification | High | Yes |
| YouTube | OAuth consent verification | High | Yes |
| TikTok | **App audit** (public posts blocked until done) | Medium | Yes (recommended first) |
| LinkedIn | **Partner approval** for org posting/analytics | Medium (org only) | Yes (recommended first) |
| X (Twitter) | Paid tier for any read/analytics | Low on Free | Yes (recommended first) |

---

## Shared backend conventions (all guides assume these)

- **Vendors** live under `app/services/vendors/<Vendor>/` as a `Client` + `Actions::<Verb>` classes
  (`.call`-style). All external knowledge stays here.
- **OAuth tokens & account ids** live on the `SocialAccount` model (`belongs_to :workspace`), with
  **encrypted** token columns. Provider-specific columns are listed in each guide; add them as
  migrations.
- **App-level secrets** (app id/secret, API keys, webhook secrets) live in **Rails encrypted
  credentials**, namespaced per vendor (`credentials.meta`, `credentials.stripe`, …).
- **Side effects** (publishing, token refresh, metric sync, generation finalization) live in
  `Operations::*` and run on **Sidekiq**; webhooks are handled by `Controllers::Webhooks::*` →
  `Operations::*` and always verify signatures.
- **Publishing** always goes through `Publishers::SocialPublisher`; **never** call a network vendor
  directly from an operation that should be provider-agnostic.

See [`../SPECIFICATION.md`](../SPECIFICATION.md) §6 (social), §5 (creatives), §8–§9 (billing) for
how these vendors slot into the data model and pipelines.
