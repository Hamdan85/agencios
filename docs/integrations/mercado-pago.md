# Mercado Pago (Brazil) — Client Billing for agencios (Pix / boleto / card / links / webhooks)

> Research current as of 2025–2026, against the official Mercado Pago developer docs.
> Use-case: agencios (agency-OS) invoicing its OWN clients, Brazil-first, Pix-first.

## 0. What you'll build (agency invoices its clients; Pix-first in Brazil)

The clean mental model for Mercado Pago (MP):

- **Pix-first, immediate, no redirect:** Create a **payment** directly via the Payments API
  (`POST /v1/payments`, `payment_method_id: "pix"`). The response carries the **copy-paste
  Pix code** (`point_of_interaction.transaction_data.qr_code`) and a **base64 QR image**
  (`qr_code_base64`) you render in your own UI. Ideal fit for an `Invoice/Charge` record.
  (https://www.mercadopago.com.br/developers/en/docs/checkout-api-payments/integration-configuration/integrate-pix)
- **Boleto:** Same `POST /v1/payments`, `payment_method_id: "bolbradesco"` — returns a
  printable boleto URL.
  (https://www.mercadopago.com.br/developers/en/docs/checkout-api-payments/integration-configuration/other-payment-methods)
- **Card:** Tokenize on the client with MercadoPago.js (token is one-time, 7-day TTL), then
  `POST /v1/payments` with the token.
  (https://www.mercadopago.cl/developers/en/docs/checkout-api-payments/integration-configuration/card/integrate-via-core-methods)
- **Hosted payment link (zero UI):** Create a **preference** (`POST /checkout/preferences`)
  and redirect the client to `init_point` (Checkout Pro). This is MP's "payment link."
  (https://www.mercadopago.com.ar/developers/en/docs/checkout-pro/overview)
- **Status truth:** Webhooks notify you of `type: "payment"` events with only `data.id`; you
  then `GET /v1/payments/{id}` to read the real `status`. Verify each webhook with the
  **x-signature HMAC**.
  (https://www.mercadopago.com.br/developers/en/docs/your-integrations/notifications/webhooks)
- **Multi-tenant (later):** Each agency connects its own MP account via **OAuth**
  (Marketplace / Split Payments); take a platform cut via `marketplace_fee` (preferences) or
  `application_fee` (payments).
  (https://www.mercadopago.com.br/developers/en/docs/split-payments/additional-content/security/oauth/creation)

Two API families you must NOT confuse:
- **Payments API (Checkout Transparente / Checkout API)** — `POST /v1/payments`. Direct/
  transparent payment on your domain. Pix QR lives at
  `point_of_interaction.transaction_data.*`. **This is what you'll use for Pix-first.**
- **Checkout Pro (Preferences API)** — `POST /checkout/preferences` returns `init_point`, an
  MP-hosted checkout URL. Minimal integration. Use only for the "send a link" case.

> Note: MP also ships a newer **Orders API** (`checkout-api-orders`) whose Pix response nests
> the QR under `transactions.payments[].payment_method.qr_code` instead of
> `point_of_interaction`. For a Pix-first agency tool the classic **Payments API** with
> `point_of_interaction` is the well-trodden path; pick one and stay consistent.

## 1. Accounts & credentials

**Where everything lives:** developers panel → **Suas integrações** (Your integrations) →
your application. Clickpath
(https://www.mercadopago.com.ar/developers/pt/docs/your-integrations/credentials):

1. Log in at the developers panel (`/developers/panel/app`).
2. Click **Suas integrações** (top right).
3. Create or open your application.
4. Left menu → **Testes > Credenciais de teste** and **Produção > Credenciais de produção**.

**Credential types** (per application):
- **Public Key** — used in the **frontend** (e.g. MercadoPago.js tokenization).
- **Access Token** — private; **always used in the backend** as
  `Authorization: Bearer <ACCESS_TOKEN>`.
- **Client ID / Client Secret** — application identifier + secret, used for **OAuth**
  (marketplace).

**TEST vs PRODUCTION**
(https://www.mercadopago.com.ar/developers/pt/docs/your-integrations/credentials,
https://www.mercadopago.com.br/developers/en/news/2025/11/19/Streamlined-integration-testing-with-automatic-credentials):
- **Test credentials** are generated **automatically when you create the application** — no
  activation needed. As of Nov 2025, creating an app for Checkout Pro / Checkout Transparente
  (Orders) / QR Code immediately yields a **test Access Token + Public Key**. Prefixed
  `TEST-...`.
- **Production credentials** require **activation**: pick industry, supply a website URL
  (mandatory), accept privacy/terms, pass reCAPTCHA. Prefixed `APP_USR-...`. Renewing
  credentials already wired into an integration **breaks** it.

**Test users / sandbox**
(https://www.mercadopago.com.ar/developers/en/docs/checkout-pro/integration-test/test-purchases):
create **test users** (one seller, one buyer) under *Your integrations > app > Test
accounts*. MP is **name-driven for outcomes** (no separate sandbox host) — force results via
the **cardholder name**:
- `APRO` = approved, `OTHE` = general decline, `CONT` = pending, `CALL` = decline w/
  authorization, `FUND` = insufficient funds, `SECU` = bad CVV, `EXPI` = expiry issue,
  `FORM` = form error.
- Test cards (CVV `123`, exp `11/30`): Visa credit `4509 9535 6623 3704`, Mastercard credit
  `5031 7557 3453 0604`, plus debit equivalents.

## 2. Core: create a payment/preference — Pix QR, boleto, card, hosted link

All Payments API calls: `POST https://api.mercadopago.com/v1/payments`, header
`Authorization: Bearer <ACCESS_TOKEN>` and a **mandatory** `X-Idempotency-Key: <unique>`.

### 2a. Pix QR (immediate) — the primary path

(https://www.mercadopago.com.br/developers/en/docs/checkout-api-payments/integration-configuration/integrate-pix,
https://www.mercadopago.com.ar/developers/en/reference/payments/_payments/post)

Request:
```
POST https://api.mercadopago.com/v1/payments
Authorization: Bearer APP_USR-xxxx
X-Idempotency-Key: 9f2c...unique
Content-Type: application/json
```
```json
{
  "transaction_amount": 100,
  "description": "Invoice #1234 - Agency services",
  "payment_method_id": "pix",
  "date_of_expiration": "2026-06-28T23:59:59.000-03:00",
  "external_reference": "invoice_1234",
  "notification_url": "https://api.youragency.com/webhooks/mercadopago",
  "payer": {
    "email": "client@example.com",
    "first_name": "Test",
    "last_name": "User",
    "identification": { "type": "CPF", "number": "19119119100" }
  }
}
```

Response (classic Payments API — **this is the exact QR path**):
```json
{
  "id": 123456789,
  "status": "pending",
  "status_detail": "pending_waiting_transfer",
  "date_of_expiration": "2026-06-28T23:59:59.000-03:00",
  "external_reference": "invoice_1234",
  "point_of_interaction": {
    "transaction_data": {
      "qr_code": "00020126580014br.gov.bcb.pix0136b76aa9c2...5204000053039865802BR...6304ABCD",
      "qr_code_base64": "iVBORw0KGgoAAAANSUhEUgAABWQ...",
      "ticket_url": "https://www.mercadopago.com.br/payments/123456789/ticket?..."
    }
  }
}
```

Exact response paths for your UI:
- **Copy-paste Pix code** → `point_of_interaction.transaction_data.qr_code`
- **QR image** (render as `data:image/png;base64,...`) → `point_of_interaction.transaction_data.qr_code_base64`
- **MP-hosted ticket page** → `point_of_interaction.transaction_data.ticket_url`

Per the docs: "`qr_code_base64` ... is used to display the QR code, while the `qr_code` field
provides the payment code that allows copying and pasting."
(https://www.mercadopago.com.br/developers/en/docs/checkout-api-payments/integration-configuration/integrate-pix)

### 2b. Boleto

(https://www.mercadopago.com.br/developers/en/docs/checkout-api-payments/integration-configuration/other-payment-methods)
Same endpoint, `payment_method_id: "bolbradesco"`. Requires fuller payer data
(`first_name`, `last_name`, `identification` CPF, full `address`).

Request:
```json
{
  "transaction_amount": 100,
  "description": "Invoice #1234",
  "payment_method_id": "bolbradesco",
  "date_of_expiration": "2026-07-05T23:59:59.000-03:00",
  "payer": {
    "email": "client@example.com",
    "first_name": "Test", "last_name": "User",
    "identification": { "type": "CPF", "number": "01234567890" },
    "address": {
      "zip_code": "88000000", "street_name": "Rua Exemplo", "street_number": "123",
      "neighborhood": "Centro", "city": "Florianópolis", "federal_unit": "SC"
    }
  }
}
```
Response:
```json
{
  "id": 5466310457,
  "status": "pending",
  "status_detail": "pending_waiting_payment",
  "transaction_details": {
    "external_resource_url": "https://www.mercadopago.com/mlb/payments/ticket/helper?payment_id=...",
    "payment_method_reference_id": "1234567890"
  }
}
```
- **Printable boleto URL** → `transaction_details.external_resource_url`. Default expiry 3
  days, configurable 1–30 days via `date_of_expiration`. Boleto approval can take up to 2
  business hours after payment.

### 2c. Card (high level)

(https://www.mercadopago.cl/developers/en/docs/checkout-api-payments/integration-configuration/card/integrate-via-core-methods)
1. **Frontend** with MercadoPago.js (Public Key) tokenizes the card → one-time `card_token`
   (valid 7 days, single use). E.g. `mp.fields.createCardToken({...})`.
2. **Backend** posts the token to `POST /v1/payments`:
```json
{
  "transaction_amount": 100,
  "token": "ff8080814c11e237014c1ff593b57b4d",
  "description": "Invoice #1234",
  "installments": 1,
  "payment_method_id": "visa",
  "issuer_id": 310,
  "payer": { "email": "client@example.com" }
}
```
`X-Idempotency-Key` mandatory. Card may settle synchronously (`status: "approved"`) or
asynchronously.

### 2d. Hosted payment link — Checkout Pro preference

`POST https://api.mercadopago.com/checkout/preferences`
(https://www.mercadopago.com.co/developers/en/reference/preferences/_checkout_preferences/post,
https://www.mercadopago.com.ar/developers/en/docs/checkout-pro/overview)

Request:
```json
{
  "items": [
    { "title": "Invoice #1234", "quantity": 1, "unit_price": 100, "currency_id": "BRL" }
  ],
  "payer": { "email": "client@example.com" },
  "external_reference": "invoice_1234",
  "notification_url": "https://api.youragency.com/webhooks/mercadopago",
  "back_urls": {
    "success": "https://app.youragency.com/invoices/1234?paid=1",
    "pending": "https://app.youragency.com/invoices/1234",
    "failure": "https://app.youragency.com/invoices/1234?failed=1"
  },
  "auto_return": "approved"
}
```
Response (key fields):
```json
{
  "id": "1234567890-abcd-...",
  "init_point": "https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=1234567890-...",
  "sandbox_init_point": "https://sandbox.mercadopago.com.br/checkout/v1/redirect?pref_id=..."
}
```
- **Send the client to** `init_point` (production) or `sandbox_init_point` (testing). This
  *is* MP's payment link for Checkout Pro. There is no separate "Payment Links" REST product
  to integrate for this use case — the dashboard "link de pagamento" is no-code, not a dev
  API surface.

## 3. Webhooks — payment status, x-signature verification, mapping to Invoice/Charge

(https://www.mercadopago.com.br/developers/en/docs/your-integrations/notifications/webhooks,
https://www.mercadopago.com.mx/developers/en/docs/checkout-pro/payment-notifications)

**Setup:** Register your `notification_url` per-app under *Your integrations > app > Webhooks
> Configure notifications*; subscribe to the **Payments** topic. The page also **reveals the
webhook secret key** here — that secret signs `x-signature`.

**Notification payload** (`type: "payment"`):
```json
{
  "id": 12345,
  "live_mode": true,
  "type": "payment",
  "date_created": "2026-06-27T10:04:58.396-03:00",
  "user_id": 44444,
  "api_version": "v1",
  "action": "payment.created",
  "data": { "id": "999999999" }
}
```
The body only gives you `data.id`. MP also appends `?data.id=999999999&type=payment` to your
URL's query string.

**x-signature verification (exact algorithm).** MP sends two headers:
- `x-signature: ts=1742505638683,v1=ced36ab6d33566bb1e16c125819b8d840d6b8ef136b0b9127c76064466f5229b`
- `x-request-id: bb56a2f1-6aae-46ac-982e-9dcd3581d08e`

Steps:
1. Split `x-signature` on `,`; from each part split on `=` to get **`ts`** and **`v1`**.
2. Read **`data.id`** from the **query string**. If alphanumeric, **lowercase it** (required
   for Orders `ORD.../PAY...` ids; numeric Pix payment ids are unaffected).
3. Build the **manifest template** literally:
   ```
   id:<data.id>;request-id:<x-request-id>;ts:<ts>;
   ```
   Official example: `id:123456;request-id:bb56a2f1-6aae-46ac-982e-9dcd3581d08e;ts:1742505638683;`
   (trailing semicolon included; omit a segment only if that input is absent).
4. Compute `HMAC_SHA256(secret, manifest)` as **hex**:
   ```js
   const cypher = crypto.createHmac('sha256', secret).update(manifest).digest('hex');
   ```
5. **Compare** `cypher` to `v1` (constant-time). Match ⇒ authentic.

(Sources: official Webhooks page shows `ts=...,v1=...`, the manifest example, and
`crypto.createHmac('sha256', secret)...digest('hex')`; corroborated by
https://github.com/mercadopago/sdk-nodejs/discussions/318)

**Then fetch the real status** — never trust the webhook for state:
```
GET https://api.mercadopago.com/v1/payments/999999999
Authorization: Bearer <ACCESS_TOKEN>
```
**Status values:** `pending`, `approved`, `authorized`, `in_process`, `in_mediation`,
`rejected`, `cancelled`, `refunded`, `charged_back`. The eight requested all exist:
**approved, pending, rejected, in_process, cancelled, refunded** (plus `authorized`,
`in_mediation`, `charged_back`).
(https://www.mercadopago.com.ar/developers/en/reference/payments/_payments/post)

**Map to Invoice/Charge:**
- Persist `external_reference` (your `invoice.id`) on creation to correlate; also store MP
  `payment_id` on the `Charge`.
- On webhook: verify signature → `GET /v1/payments/{id}` → update `Charge.status`; mark
  `Invoice` paid when `approved`.
- Idempotency: webhooks may arrive multiple times / out of order — key sync on `payment_id`
  and only move state forward.

## 4. Marketplace / split (OAuth so each agency connects its own MP account, platform fee)

For multi-tenant where each agency receives money in **its own** MP account and the platform
skims a fee, use **Split Payments (Marketplace)** with **OAuth**.
(https://www.mercadopago.com.br/developers/en/docs/split-payments/additional-content/security/oauth/creation,
https://www.mercadopago.com.mx/developers/en/docs/split-payments/integration-configuration/integrate-marketplace)

**OAuth flow (per agency):**
1. Redirect the agency to authorize:
   ```
   https://auth.mercadopago.com/authorization?response_type=code&client_id=<APP_ID>&platform_id=mp&state=<unique>&redirect_uri=<YOUR_URL>&code_challenge=<CHALLENGE>&code_challenge_method=S256
   ```
   PKCE supported: `code_challenge = BASE64URL(SHA256(code_verifier))`, `code_verifier`
   43–128 chars. Authorization `code` valid 10 minutes.
2. Exchange the code: `POST https://api.mercadopago.com/oauth/token`
   ```json
   {
     "client_id": "<APP_ID>",
     "client_secret": "<APP_SECRET>",
     "grant_type": "authorization_code",
     "code": "TG-XXXXXXXX-241983636",
     "redirect_uri": "<YOUR_URL>",
     "code_verifier": "47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU"
   }
   ```
   Response:
   ```json
   {
     "access_token": "APP_USR-...",
     "token_type": "bearer",
     "expires_in": 15552000,
     "scope": "offline_access payments write",
     "user_id": 123456789,
     "refresh_token": "TG-...",
     "public_key": "APP_USR-...",
     "live_mode": true
   }
   ```
   Connected-account **access_token valid 180 days (6 months)**; refresh before expiry with
   `grant_type: "refresh_token"` (or the agency re-authorizes). Store `access_token`,
   `refresh_token`, `user_id`, expiry **per agency** (encrypted).

**Taking the platform fee:**
- **Checkout Pro:** add `marketplace_fee` to the **preference** (`POST /checkout/preferences`),
  created with the **agency's** OAuth access token.
- **Checkout Transparente / Payments:** add `application_fee` to the **payment**
  (`POST /v1/payments`), again using the **agency's** OAuth access token.
- Deduction order: **MP's commission first**, then your marketplace/application fee from the
  remainder; the agency receives what's left.

Example (transparent payment with fee, using the agency's token):
```json
{
  "transaction_amount": 100,
  "payment_method_id": "pix",
  "application_fee": 10,
  "description": "Invoice #1234",
  "payer": { "email": "client@example.com" }
}
```

**Relevance to multi-tenant:** in single-tenant you use the agency's own Access Token directly
(no OAuth). For the per-agency SaaS, each agency connects its MP account via OAuth once; store
their token and pass `marketplace_fee`/`application_fee`. OAuth/split availability can be
account-gated by MP and isn't needed for the initial single-agency Pix-first build.

## 5. Backend plan

Follows agencios conventions: vendors under `app/services/vendors/MercadoPago/` (`Client` +
`Actions::<Verb>`); operations in `app/services/operations/`; webhooks via
`Controllers::Webhooks::*` → `Operations::*`; secrets in Rails encrypted credentials; Sidekiq
for async.

**Credentials** (`rails credentials:edit`):
```yaml
mercado_pago:
  access_token: APP_USR-...      # backend; used as Bearer
  public_key: APP_USR-...        # frontend tokenization (card)
  webhook_secret: <secret>       # signs x-signature
  client_id: ...                 # OAuth (marketplace, later)
  client_secret: ...
```

**Model: `Charge`** (one per payment attempt; `Invoice has_many :charges`):
`invoice_id`, `mp_payment_id` (unique), `method` (`pix`/`boleto`/`card`/`checkout_pro`),
`status` (string enum), `amount_cents`, `external_reference`, plus Pix fields `pix_qr_code`,
`pix_qr_code_base64`, `ticket_url`, `expires_at`. `Invoice` has `status`
(`open/paid/overdue/canceled`), marked paid when a `Charge` reaches `approved`.

**API → Action mapping:**

| MP API call | Action class |
|---|---|
| `POST /v1/payments` (Pix / boleto / card) | `Vendors::MercadoPago::Actions::CreatePayment` |
| `POST /checkout/preferences` | `Vendors::MercadoPago::Actions::CreatePreference` |
| `GET /v1/payments/{id}` | `Vendors::MercadoPago::Actions::GetPayment` |
| `POST /oauth/token` (auth_code + refresh) | `Vendors::MercadoPago::Actions::ExchangeOAuthToken` *(marketplace, later)* |

**Operations / controllers:**
- `Operations::Billing::CreateInvoice` — builds `Invoice` + first `Charge`, calls
  `Actions::CreatePayment` (Pix default) or `Actions::CreatePreference`, persists QR/ticket
  fields, returns the record.
- `Operations::Billing::SyncPaymentStatus` — given `mp_payment_id`, calls
  `Actions::GetPayment`, maps MP status → `Charge.status`, transitions `Invoice`
  (move-forward only). Runs from the webhook AND from a Sidekiq reconciliation cron (Pix can
  be paid without a webhook arriving promptly).
- `Controllers::Webhooks::MercadoPago` — verifies `x-signature`, enqueues a job that calls
  `Operations::Billing::SyncPaymentStatus`. Responds `200` fast (ack within ~22s or MP
  retries).

**`Vendors::MercadoPago::Client` (sketch):**
```ruby
module Vendors
  module MercadoPago
    class Client
      BASE = "https://api.mercadopago.com".freeze

      def initialize(access_token: Rails.application.credentials.dig(:mercado_pago, :access_token))
        @access_token = access_token
      end

      def create_payment(body:, idempotency_key:)
        post("/v1/payments", body, "X-Idempotency-Key" => idempotency_key)
      end

      def create_preference(body:)
        post("/checkout/preferences", body)
      end

      def get_payment(id)
        get("/v1/payments/#{id}")
      end

      private

      def post(path, body, extra_headers = {})
        request(:post, path, json: body, headers: extra_headers)
      end

      def get(path)
        request(:get, path)
      end

      def request(verb, path, json: nil, headers: {})
        resp = Faraday.public_send(verb, "#{BASE}#{path}") do |req|
          req.headers["Authorization"] = "Bearer #{@access_token}"
          req.headers["Content-Type"]  = "application/json"
          headers.each { |k, v| req.headers[k] = v }
          req.body = JSON.generate(json) if json
        end
        parsed = resp.body.present? ? JSON.parse(resp.body) : {}
        raise Error.new(resp.status, parsed) unless resp.success?
        parsed
      end

      class Error < StandardError
        def initialize(status, body); super("MercadoPago #{status}: #{body}"); end
      end
    end
  end
end
```

**`Actions::CreatePayment` (Pix) (sketch):**
```ruby
module Vendors
  module MercadoPago
    module Actions
      class CreatePayment < Vendors::Base   # exposes .call -> new(...).call
        def initialize(amount:, description:, payer:, external_reference:,
                       method: "pix", expires_at: nil, extra: {})
          @amount = amount; @description = description; @payer = payer
          @external_reference = external_reference; @method = method
          @expires_at = expires_at; @extra = extra
        end

        def call
          body = {
            transaction_amount: @amount,
            description: @description,
            payment_method_id: @method,                       # "pix" | "bolbradesco" | card brand
            external_reference: @external_reference,
            notification_url: SystemConfig.app_host + "/webhooks/mercadopago",
            payer: @payer
          }
          body[:date_of_expiration] = @expires_at.iso8601(3) if @expires_at
          body.merge!(@extra)                                  # token/installments/issuer_id for card

          Client.new.create_payment(body: body, idempotency_key: SecureRandom.uuid)
          # => response.dig("point_of_interaction","transaction_data","qr_code" | "qr_code_base64" | "ticket_url")
        end
      end
    end
  end
end
```

**`Controllers::Webhooks::MercadoPago` (signature verification) (sketch):**
```ruby
module Controllers
  module Webhooks
    class MercadoPago < Controllers::Base
      SECRET = Rails.application.credentials.dig(:mercado_pago, :webhook_secret)

      def initialize(headers:, query:, body:)
        @headers = headers; @query = query; @body = body
      end

      def call
        return :unauthorized unless valid_signature?
        data_id = @query["data.id"] || @body.dig("data", "id")
        return :ok if data_id.blank?
        SyncMercadoPagoPaymentJob.perform_async(data_id.to_s)   # -> Operations::Billing::SyncPaymentStatus
        :ok
      end

      private

      def valid_signature?
        sig  = @headers["x-signature"].to_s
        parts = sig.split(",").map { |p| p.split("=", 2) }.to_h
        ts, v1 = parts["ts"], parts["v1"]
        return false if ts.blank? || v1.blank?

        data_id = @query["data.id"].to_s
        data_id = data_id.downcase if data_id.match?(/[a-z]/i)  # MP lowercases alphanumeric ids
        request_id = @headers["x-request-id"].to_s

        manifest = "id:#{data_id};request-id:#{request_id};ts:#{ts};"
        expected = OpenSSL::HMAC.hexdigest("SHA256", SECRET, manifest)
        ActiveSupport::SecurityUtils.secure_compare(expected, v1)
      end
    end
  end
end
```

The thin Rails controller passes `request.headers`, `request.query_parameters`, and the
parsed JSON body into `Controllers::Webhooks::MercadoPago.call`, then renders `head :ok`
quickly. `Operations::Billing::SyncPaymentStatus` does the `GetPayment` + state mapping.

## 6. Gotchas & testing checklist

- **`X-Idempotency-Key` is mandatory** on `POST /v1/payments` — one UUID per `Charge`
  attempt, persisted so retries don't double-charge.
- **Don't trust the webhook body for status** — it only carries `data.id`. Always
  `GET /v1/payments/{id}`. Webhooks can be duplicated / out of order / delayed; reconcile
  move-forward only and run a Sidekiq sweep for Pix.
- **`x-signature` manifest exactness:** trailing semicolons matter; `data.id` comes from the
  **query string**; **lowercase** alphanumeric ids before hashing. A mismatch is almost
  always a wrong secret (test vs prod), wrong `data.id` source, or casing. Test secret ≠ prod
  secret.
- **Two API shapes for Pix QR:** classic Payments API →
  `point_of_interaction.transaction_data.qr_code(_base64)`; newer Orders API →
  `transactions.payments[].payment_method.qr_code`. Pick Payments API; don't mix parsers.
- **Pix `date_of_expiration`** controls how long the QR is payable; render `qr_code_base64`
  as `data:image/png;base64,...`, offer `qr_code` as copy-paste.
- **Boleto** needs full payer `address` + CPF and takes up to 2 business hours to confirm;
  default expiry 3 days.
- **Card token** is single-use, expires in 7 days — tokenize right before paying.
- **Credentials prefixes:** test = `TEST-...`, prod = `APP_USR-...`. Production requires
  activation (industry, website URL, terms, reCAPTCHA). As of Nov 2025 test credentials are
  auto-issued on app creation.
- **Testing:** create test users (seller/buyer); use test cards (CVV 123, exp 11/30); drive
  outcomes via cardholder name `APRO/CONT/OTHE/...`; for Checkout Pro use `sandbox_init_point`.
- **OAuth tokens expire in 180 days** — schedule a refresh job before expiry or agencies
  silently stop receiving funds.
- **Webhook ack window:** respond `200`/`201` quickly (within ~22s) or MP retries; do heavy
  work in Sidekiq.

---

### Findings I could NOT fully verify from official docs

- **Exact `point_of_interaction` JSON block on the Payments-API Pix page** renders via JS;
  the *paths* (`qr_code`, `qr_code_base64`, `ticket_url`) were confirmed in prose + the API
  reference, but the literal full envelope was reconstructed from those confirmed paths. Paths
  themselves are confirmed.
- **The literal manifest template** (`id:123456;request-id:...;ts:...;` +
  `crypto.createHmac('sha256', secret)...digest('hex')`) was surfaced via search snippets of
  the official webhooks page and corroborated by MP's sdk-nodejs discussion #318. Confident in
  the template; verify once against a live `x-signature`.
- **`data.id` lowercasing** is documented behavior for alphanumeric ids (Orders) and standard
  in SDKs; no single official prose sentence stating it was found. Numeric Pix payment ids are
  unaffected.
- **The `_payments/post` and `_checkout_preferences/post` reference pages returned HTTP 400**
  to WebFetch on several locales; field lists/status values confirmed from integration guides
  + search instead. `init_point`/`sandbox_init_point` and preference fields are confirmed.
- **No distinct "Payment Links" REST product** separate from Checkout Pro preferences was
  found in the developer docs — `init_point` is the documented hosted-link mechanism.
