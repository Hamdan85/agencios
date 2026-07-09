# Stripe — SaaS Billing for agencios Workspaces (seat plans + prepaid credit packs)

> Research current as of 2025–2026, against official Stripe docs.
> agencios pricing: subscription plans **Solo** (1 person), **Agência** (5–20 people),
> **Enterprise** (20+) — each a single **licensed** seat item. Generation usage (video/image) is
> **NOT** Stripe-metered; it is billed from the workspace's prepaid `CreditWallet`, and credit
> packs are bought via a one-time Stripe Checkout.

> **Historical note:** an earlier design used Stripe Billing Meters for usage. That was replaced
> by prepaid credits. The Billing-Meters sections below (§1's metered-price examples onward) are
> kept only as Stripe API reference and are **NOT** used by agencios — there are no meters, no
> meter events, and no metered subscription items in the live system.

## 0. Billing model overview (seat plans + prepaid credits)

A **single Stripe Subscription per workspace** containing **exactly one subscription item**:

- **One licensed item** = the plan/seats (fixed recurring price, with `quantity`). `quantity`
  is only allowed on `recurring.usage_type=licensed` prices.
  (https://docs.stripe.com/subscriptions/pricing-models/per-seat-pricing.md,
  https://docs.stripe.com/billing/subscriptions/quantities.md)
- **No metered items, no Billing Meters, no meter events.**

**Plan prices are DB-driven.** `PricingPlan.price_cents` is the source of truth; saving a plan in
`/admin` pushes it to Stripe as a recurring **Price** via `Operations::Billing::SyncPlanToStripe`
(`Vendors::Stripe::Actions::SyncPlanPrices` / `ProvisionPlanPrices`). Seat count is reconciled to
the licensed item's `quantity` by `Operations::Billing::ReconcileSeats`.

**Generation usage = prepaid credits (not Stripe).** Video and image generations debit the
workspace's `CreditWallet` via `Operations::Credits::Debit` (cost-plus pricing via
`Pricing.credits_for`); carousels are included in the plan (0 credits). Customers top up by
**buying credit packs** through a **one-time Stripe Checkout** using inline `price_data` (no
pre-created Stripe Price) — `Vendors::Stripe::Actions::CreateCreditCheckoutSession`; the
`checkout.session.completed` webhook grants the credits via `Operations::Credits::Grant`.

The subscription Checkout itself carries only the one licensed line
(https://docs.stripe.com/api/checkout/sessions/create.md), and all items on a subscription roll
into one invoice per period in one currency
(https://docs.stripe.com/billing/subscriptions/multiple-products.md).

## 1. Products & Prices setup in Stripe (clickpath + API)

### Plan tiers — per-seat licensed vs flat tiers (recommendation)

For Solo (1), Agência (5–20), Enterprise (20+), the cleanest model is **per-seat licensed
pricing** with `quantity` = seats — Stripe maps seats directly to subscription-item
`quantity`, and portal/proration handle seat changes automatically
(https://docs.stripe.com/subscriptions/pricing-models/per-seat-pricing.md,
https://docs.stripe.com/billing/subscriptions/quantities.md). Three viable shapes:

- **Pure per-seat (recommended for Agência):** one licensed Price `agencia_seat_monthly`,
  `quantity` = seats. Enforce the 5–20 band with `adjustable_quantity[minimum]=5`,
  `maximum=20` in Checkout (https://docs.stripe.com/payments/checkout/adjustable-quantity.md).
- **Flat-tier per plan:** three distinct licensed Prices (Solo/Agência/Enterprise) each at
  `quantity=1`. Simpler, but loses automatic per-seat proration; better if tiers are
  feature-differentiated bundles.
- **Hybrid (good fit here):** a flat **platform base fee** Price + a **per-seat** Price as two
  licensed items on the same subscription
  (https://docs.stripe.com/billing/subscriptions/multiple-products.md).

**Concrete advice:** **Solo** = single licensed price qty 1 (flat). **Agência** = per-seat
licensed price, qty 5–20, with adjustable-quantity bounds. **Enterprise** = per-seat (or
custom quote / Stripe-billed invoice), qty 20+. Metered overage applies identically to all
three.

### Use `lookup_key` for every price

Resolve prices by lookup key so price IDs aren't hard-coded; create prices with `lookup_key`
(e.g. `solo_monthly`, `agencia_seat_monthly`, `usage_carousel_monthly`, `usage_video_monthly`).

### Clickpath (Dashboard)

1. **Product catalog → Add product** for each plan; add a recurring **Price**, `usage_type=licensed`.
2. **Billing → Meters → Create meter** (two meters: `carousel_generation`, `video_generation`).
3. Creating a meter in the Dashboard lets you **create the associated metered Price in the
   same flow**; or create a metered Price under a "Usage" product and pick the meter
   (`usage_type=metered` + `recurring.meter=<meter_id>`).

### API — licensed plan price

```bash
curl https://api.stripe.com/v1/prices \
  -u "rk_live_...:" \
  -d currency=brl \
  -d product=prod_AGENCIA \
  -d unit_amount=19000 \
  -d "recurring[interval]=month" \
  -d "recurring[usage_type]=licensed" \
  -d lookup_key=agencia_seat_monthly
```

### API — metered overage price tied to a meter

`recurring` fields: `interval`, `interval_count`, `usage_type` (`licensed`|`metered`, default
`licensed`), `meter` (required for metered). `billing_scheme` is `per_unit` or `tiered`;
tiered needs `tiers_mode` (`graduated`|`volume`) + `tiers`
(https://docs.stripe.com/api/prices/create.md).

```bash
# per-unit metered example
curl https://api.stripe.com/v1/prices \
  -u "rk_live_...:" \
  -d currency=brl \
  -d product=prod_USAGE \
  -d billing_scheme=per_unit \
  -d unit_amount=150 \
  -d "recurring[interval]=month" \
  -d "recurring[usage_type]=metered" \
  -d "recurring[meter]=mtr_carousel_..." \
  -d lookup_key=usage_carousel_monthly
```

For "X included, then overage," use `billing_scheme=tiered` + `tiers_mode=graduated`: tier 1
(`up_to=<included quota>`, `unit_amount=0`), tier 2 (`up_to=inf`, `unit_amount=<overage>`).
Standard free-tier-allowance pattern (see §7).

## 2. Meters — create, event_name, reporting usage, customer mapping, aggregation

### Create a meter (https://docs.stripe.com/api/billing/meter/create.md)

`POST /v1/billing/meters`
- `display_name` (≤250) — required
- `event_name` (≤100) — required; the name your meter events must carry
- `default_aggregation.formula` — required; `sum` | `count` | `last`
- `value_settings.event_payload_key` (≤100) — payload key whose numeric value is aggregated
  (use `value`; ignored when formula is `count`)
- `customer_mapping.type` = `by_id` (only option), `customer_mapping.event_payload_key` (≤100)
  — payload key holding the Stripe customer id (use `stripe_customer_id`)
- `event_time_window` (optional) — `hour` | `day` pre-aggregation bucket

**carousel_generation meter:**
```bash
curl https://api.stripe.com/v1/billing/meters \
  -u "rk_live_...:" \
  -d display_name="Carousel Generations" \
  -d event_name=carousel_generation \
  -d "default_aggregation[formula]=sum" \
  -d "value_settings[event_payload_key]=value" \
  -d "customer_mapping[type]=by_id" \
  -d "customer_mapping[event_payload_key]=stripe_customer_id"
```

Response (`object: "billing.meter"`) includes `id` (e.g. `mtr_test_...`), `status: "active"`,
and echoes config. Create a second identical meter with `event_name=video_generation`.
**Aggregation choice:** use `sum` over a `value` of `1` per generation (lets you later weight
expensive generations >1); `count` ignores `value`; `last` is for gauges (not relevant here).

### Reading aggregated usage (https://docs.stripe.com/api/billing/meter-event-summary/list.md)

`GET /v1/billing/meters/{id}/event_summaries?customer=cus_...&start_time=...&end_time=...`
returns `aggregated_value` per window — useful for in-app usage dashboards and free-tier
remaining counts. **Note:** events process **asynchronously**, so summaries/upcoming invoices
may lag recently-sent events
(https://docs.stripe.com/billing/subscriptions/usage-based/recording-usage.md).

## 3. Subscription creation — Checkout Session (and API)

### Checkout (recommended)

`mode=subscription`, `line_items` = base licensed price **with `quantity`** + each metered
price **without `quantity`** (https://docs.stripe.com/api/checkout/sessions/create.md,
https://docs.stripe.com/billing/subscriptions/usage-based.md). Max 20 recurring line items.

```json
{
  "mode": "subscription",
  "customer": "cus_123",
  "line_items": [
    { "price": "price_agencia_seat_monthly", "quantity": 8,
      "adjustable_quantity": { "enabled": true, "minimum": 5, "maximum": 20 } },
    { "price": "price_usage_carousel_monthly" },
    { "price": "price_usage_video_monthly" }
  ],
  "subscription_data": { "trial_period_days": 14, "metadata": { "workspace_id": "42" } },
  "success_url": "https://app.agencios.com/billing?session_id={CHECKOUT_SESSION_ID}",
  "cancel_url": "https://app.agencios.com/precos"
}
```

The metered lines deliberately omit `quantity`. Per Stripe's current guidance, **do not pass
`payment_method_types`** — omit it to enable dynamic payment methods.

### API-only path

`POST /v1/subscriptions` with `customer` + `items[]` (one licensed item with `quantity`, the
metered items without). Multiple items on one subscription confirmed
(https://docs.stripe.com/billing/subscriptions/multiple-products.md). Use
`payment_behavior=default_incomplete` + confirm a PaymentIntent client-side if you build your
own form; Checkout avoids that complexity.

## 4. Reporting usage from agencios — meter events + idempotency

When a carousel or video is generated, emit a meter event.

### Standard path (https://docs.stripe.com/api/billing/meter-event/create.md)

`POST /v1/billing/meter_events`
- `event_name` — required; matches the meter's `event_name`
- `payload` — object with `stripe_customer_id` and `value` (keys must match the meter's
  mappings)
- `identifier` (optional) — **dedup/idempotency key**, UUID recommended; uniqueness enforced
  for ~24h+
- `timestamp` (optional) — Unix seconds; must be within the **past 35 days** or ≤5 min in the
  future; defaults to now

```bash
curl https://api.stripe.com/v1/billing/meter_events \
  -u "rk_live_...:" \
  -d event_name=carousel_generation \
  -d "payload[stripe_customer_id]=cus_123" \
  -d "payload[value]=1" \
  -d identifier=carousel_gen_988fc \
  -d timestamp=1735689600
```

### High-throughput path (Meter Event Stream, v2)

For high volume: `POST /v2/billing/meter_event_session` → session auth token valid 15 min,
then POST events to `https://meter-events.stripe.com/v2/billing/meter_event_stream` with
`Authorization: Bearer <session token>`, up to 100 events/request, up to 10,000 req/s livemode
(https://docs.stripe.com/api/v2/billing/meter-event-stream/create.md,
https://docs.stripe.com/changelog/acacia/2024-09-30/usage-based-billing-v2-meter-events-api.md).
For agencios's per-generation volume, the standard `/v1` endpoint is fine.

### `Operations::Billing::RecordUsage` pattern + idempotency

Derive the meter event `identifier` **deterministically from the generated record's id** (e.g.
`"carousel:#{generation.id}"`). If the Sidekiq job retries, Stripe dedups within its 24h
window, so a single generation is never double-billed. Combine with `value=1` and the
workspace's `stripe_customer_id`. Run from a Sidekiq job so a Stripe outage doesn't block the
user's generation; persist a `metered_at` timestamp so you can detect/replay gaps.

## 5. Webhooks to handle + customer portal

### Webhooks (https://docs.stripe.com/billing/subscriptions/webhooks.md,
https://docs.stripe.com/changelog/basil/2025-03-31/billing-meter-webhooks.md)

Core subscription lifecycle:
- `checkout.session.completed` — fetch the created subscription, persist locally.
- `customer.subscription.created` / `.updated` / `.deleted` — sync status, items, seat
  quantity; `.deleted` ⇒ revoke access.
- `customer.subscription.trial_will_end` — fires ~3 days before trial end; nudge to add a card.
- `invoice.paid` — provision/extend access; this invoice **includes metered usage charges**
  for the period.
- `invoice.payment_failed` — notify, let Smart Retries/dunning run; don't revoke on first
  failure.
- `invoice.finalized` (optional) — invoice ready; surface the upcoming amount including usage.

Meter-specific (added in `2025-03-31.basil`):
- `v1.billing.meter.error_report_triggered` — **the important one**: Stripe processes meter
  events asynchronously and emits this when ingested events had errors (unknown customer id,
  missing payload key, no matching meter). Handle it to alert/repair — silently dropped events
  mean unbilled usage. (https://docs.stripe.com/billing/subscriptions/usage-based/alerts.md)
- `billing.meter.created` / `.updated` / `.deactivated` / `.reactivated` — meter config
  lifecycle; optional.

Idempotency: dedup on `event.id`.

### Customer portal (https://docs.stripe.com/api/customer_portal/sessions/create.md,
https://docs.stripe.com/customer-management/integrate-customer-portal.md)

`POST /v1/billing_portal/sessions` with `customer` (required), `return_url`, optional
`configuration`, optional `flow_data` (deep links). Returns a `url` to redirect to. The portal
lets customers: update/replace payment method, view invoices & billing history, cancel, and
(if enabled) upgrade/downgrade/change quantity. Features governed by
`POST /v1/billing_portal/configurations` (`features.subscription_update`,
`.subscription_update.products`, `.subscription_cancel`, `.payment_method_update`,
`.invoice_history`). To let customers change plan/seats in the portal, enable
`subscription_update` and list allowed products.

## 6. Backend plan

Conventions: vendors under `app/services/vendors/<Vendor>/` (`Client` + `Actions::<Verb>`);
operations in `app/services/operations/`; secrets in Rails encrypted credentials; Sidekiq;
webhooks via `Controllers::Webhooks::*` → `Operations::*`. (If you mirror an existing repo
where subscription billing is nested under `Vendors::Stripe::Billing::*` to separate it from
connected-account Stripe Connect calls, keep that nesting — add metering to the `Billing`
namespace rather than a parallel top-level one.)

**Secrets** stay in `Rails.application.credentials.stripe` (`secret_key`,
`billing_webhook_secret`).

| Concern | Class | Stripe call |
|---|---|---|
| Platform client | `Vendors::Stripe::Client` (or `Vendors::Stripe::Billing::Client`) — add `create_meter_event`, `create_meter`, `list_event_summaries` | — |
| Checkout w/ usage | `Vendors::Stripe::Actions::CreateCheckoutSession` | `POST /v1/checkout/sessions` |
| Report usage | `Vendors::Stripe::Actions::ReportMeterEvent` | `POST /v1/billing/meter_events` |
| Portal | `Vendors::Stripe::Actions::CreatePortalSession` | `POST /v1/billing_portal/sessions` |
| Record usage op | `Operations::Billing::RecordUsage` | → ReportMeterEvent |
| Sync subscription | `Operations::Billing::SyncSubscription` | reads subscription |
| Webhook | `Controllers::Webhooks::Stripe` | verify + dispatch |
| Model | `Subscription belongs_to :workspace` | — |

**Client (extension sketch):**
```ruby
module Vendors::Stripe
  class Client
    # ...existing methods...

    def create_meter_event(event_name:, stripe_customer_id:, value:, identifier:, timestamp: nil)
      ::Stripe::Billing::MeterEvent.create({
        event_name:,
        payload:   { stripe_customer_id:, value: value.to_s },
        identifier:,
        timestamp:
      }.compact)
    end
  end
end
```

**ReportMeterEvent action:**
```ruby
module Vendors::Stripe::Actions
  class ReportMeterEvent
    def self.call(event_name:, stripe_customer_id:, value:, identifier:, timestamp: nil)
      Client.new.create_meter_event(
        event_name:, stripe_customer_id:, value:, identifier:, timestamp:
      )
    end
  end
end
```

**RecordUsage operation — idempotency keyed off the generated record id:**
```ruby
module Operations::Billing
  class RecordUsage < Operations::Base
    EVENT_NAMES = { carousel: "carousel_generation", video: "video_generation" }.freeze

    def initialize(generation:)
      @generation = generation
    end

    def call
      sub = @generation.workspace.subscription
      return if sub&.stripe_customer_id.blank? # not billed / free internal

      Vendors::Stripe::Actions::ReportMeterEvent.call(
        event_name:         EVENT_NAMES.fetch(@generation.kind.to_sym),
        stripe_customer_id: sub.stripe_customer_id,
        value:              1,
        identifier:         "#{@generation.kind}:#{@generation.id}", # dedup key
        timestamp:          @generation.created_at.to_i
      )
      @generation.update!(metered_at: Time.current)
    end
  end
end
```

Call it from a Sidekiq job (`RecordUsageJob`) enqueued when a generation completes, so
generation never blocks on Stripe and retries are safe (Stripe dedups the `identifier`).

**Webhook handler (handled list):**
```ruby
HANDLED = %w[
  checkout.session.completed
  customer.subscription.created customer.subscription.updated customer.subscription.deleted
  invoice.paid invoice.payment_failed customer.subscription.trial_will_end
  v1.billing.meter.error_report_triggered
].freeze

# in #handle:
when "v1.billing.meter.error_report_triggered"
  Operations::Billing::Notifications.call(kind: :meter_error, event: event.data.object)
```
Dedup via a `StripeEvent.create_or_find_by!(stripe_event_id: event.id)` guard makes handling
idempotent.

## 7. Gotchas (meter event timing, idempotency keys, proration, free-tier) & testing checklist

**Gotchas:**
- **Async processing lag** — meter events aggregate asynchronously; summaries/upcoming invoice
  may not reflect a just-sent event
  (https://docs.stripe.com/billing/subscriptions/usage-based/recording-usage.md). Don't gate
  UI on immediate Stripe reflection; track usage locally too.
- **Watch `v1.billing.meter.error_report_triggered`** — events with an unknown
  `stripe_customer_id`, missing payload key, or no matching meter are **silently dropped** =
  unbilled usage. Subscribe and alert.
- **Idempotency `identifier`** — uniqueness window ~24h+. For longer-horizon safety, store
  `metered_at` locally and skip already-metered records. Derive `identifier` from the
  immutable generation id, never a timestamp.
- **`timestamp` window** — must be within the past 35 days; can't backfill older usage via the
  standard API. Don't let a stuck queue exceed 35 days.
- **Metered prices reject `quantity`** in Checkout and on subscription items — only the
  licensed/seat item carries `quantity`.
- **Currency** — all items on one subscription must share a currency.
- **Proration** — seat (licensed) changes prorate normally; **metered usage does not prorate**
  (billed for what was used). Mid-cycle plan switches need care with metered carry-over.
- **Legacy API removed** — `usage_records` / `usage_record_summaries` and `usage_type=metered`
  *without* a `meter` are **removed in `2025-03-31.basil`**
  (https://docs.stripe.com/changelog/basil/2025-03-31/deprecate-legacy-usage-based-billing.md,
  https://docs.stripe.com/billing/subscriptions/usage-based-legacy/migration-guide.md). Build
  new on Meters from day one.

**Free-tier allowance** — two clean options: (a) **tiered graduated metered price** with a
first tier at `unit_amount=0` up to the included quota, then overage above (purely in Stripe);
or (b) keep the allowance in your app and only emit meter events for generations **beyond** the
included quota. (a) is auditable and self-contained; (b) gives app-side control and simpler
per-unit pricing. Recommend (a) unless allowances vary dynamically.

**API version** — set `Stripe.api_version` explicitly so webhook payload shapes are stable.
Recent versions moved `invoice.subscription` to `invoice.parent.subscription_details.subscription`
— handle both if you support multiple versions.

**Testing checklist:**
- `stripe sandbox create` for keys; `stripe trigger v1.billing.meter.error_report_triggered`
  and the invoice/subscription events to exercise handlers.
- Create both meters + metered prices in test mode; run a Checkout with one licensed (qty) +
  two metered (no qty) line items; confirm one subscription with three items.
- Emit `meter_events` with a fixed `identifier`, send twice, confirm only one is counted
  (dedup).
- Pull `event_summaries`, confirm `aggregated_value`.
- Advance the clock / let the period close; confirm `invoice.paid` includes both base seat
  charge and usage line items.
- Verify portal lets customers change payment method, cancel, and (if enabled) change seats;
  confirm seat change triggers `customer.subscription.updated` → `SyncSubscription`.
- Webhook idempotency: redeliver an event from the Dashboard, confirm the second delivery is a
  no-op.

---

### Findings I could NOT fully verify from official docs

- **`v1.billing.meter.no_meter_found` event** — confirmed
  `v1.billing.meter.error_report_triggered` and the four `billing.meter.created/updated/
  deactivated/reactivated` events from the changelog; "no_meter_found" appeared in search
  context but no doc page lists it verbatim. Treat error handling as primarily
  `error_report_triggered`; check the live events reference (https://docs.stripe.com/api/events.md)
  before relying on others.
- **v2 meter event stream host/path exactness** — `meter-events.stripe.com/v2/billing/
  meter_event_stream` and the 15-min token / 100-events / 10k-rps figures came from the v2
  reference + search; SDK helpers abstract these. Confirm via official stripe-ruby v2 examples
  if you implement (you likely won't need the stream for this volume).
- **Legacy migration-guide URL** — the working path is `…/usage-based-legacy/migration-guide`
  (the `…/legacy-usage-based-billing/migration-guide` variant 404s).
- **Stripe's strategic steer toward Metronome** for *new* UBB integrations is real and worth a
  deliberate decision; this doc documents the Billing Meters path you asked to verify, which is
  fully supported for the simple two-meter case here.
