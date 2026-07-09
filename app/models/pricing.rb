# frozen_string_literal: true

# Facade over the pricing catalog. Everything money-facing resolves here so the
# landing page, in-app billing, Stripe checkout, and the credit-debit path all
# agree.
#
# What is configurable vs. what is math:
#   * ADMIN configures ONLY two things — Subscriptions (PricingPlan) and Credit
#     Packs (PricingPack). They define HOW MUCH and HOW we charge: the plan/pack
#     prices, seats, clients, included credits, and Stripe pointers. The DB is the
#     SOURCE OF TRUTH for the price: saving a plan pushes it to Stripe
#     (Operations::Billing::SyncPlanToStripe); packs use inline price_data.
#   * EVERYTHING ELSE is math — the cost-plus formula that derives a generation's
#     credit cost from real vendor cost. Those are fixed code CONSTANTS below,
#     revised by a deploy (never admin-tunable, never indexed to a live FX rate).
#
# Margin model: a credit is worth CREDIT_UNIT_CENTS at retail and a generation is
# charged at ~MARKUP× vendor cost (≈80% gross margin).
module Pricing
  module_function

  # Technical (non-commercial) constants.
  DEFAULT_VIDEO_SECONDS = 30 # default video length when a caller gives none
  CREDIT_PACK_TTL = 12.months # how long purchased credits last
  VIDEO_DISPLAY_SECONDS = 15 # the "por Ns" anchor shown on marketing/billing

  # ── Credit-economy math — fixed code constants, NOT admin-tunable ──────────
  CREDIT_UNIT_CENTS = 100    # 1 credit = R$1 at retail
  MARKUP            = 6.5    # revenue = MARKUP × vendor cost (≈80% gross margin)
  USD_BRL           = 6.00   # fixed conservative USD→BRL (spot + buffer; revised in code)
  VIDEO_USD_PER_SEC = 0.16   # per-second rate for the up-front video hold (real cost trues-up)
  IMAGE_CREDITS     = 1      # flat cost per image
  CAROUSEL_CREDITS  = 1      # flat cost per carousel

  # ── Commercial policy — fixed code constants ───────────────────────────────
  TRIAL_DAYS = 7
  ANNUAL_DISCOUNT_PERCENT = 15

  DEFAULT_PLANS = [
    {
      key: 'solo', name: 'Solo', stripe_lookup_key: 'solo_monthly', stripe_annual_lookup_key: 'solo_yearly',
      price_cents: 9_900, seats: 2, clients: 3, included_credits: 40,
      features: [
        '2 assentos', 'Até 3 clientes', 'Quadro de produção completo',
        'Legendas e textos com IA inclusos',
        '40 créditos/mês para vídeos, imagens e carrosséis', 'Integrações sociais diretas'
      ]
    },
    {
      key: 'agencia', name: 'Agência', stripe_lookup_key: 'agencia_monthly', stripe_annual_lookup_key: 'agencia_yearly',
      price_cents: 34_900, seats: 20, clients: 25, included_credits: 200,
      features: [
        'Até 20 assentos', 'Até 25 clientes', 'Tudo do Solo',
        '200 créditos/mês para vídeos, imagens e carrosséis',
        'Faturamento de clientes (Mercado Pago)', 'Calendário e reuniões (Google)',
        'Aprovações de cliente e relatórios com IA'
      ]
    },
    {
      key: 'enterprise', name: 'Enterprise', stripe_lookup_key: 'enterprise_monthly', stripe_annual_lookup_key: 'enterprise_yearly',
      price_cents: 99_900, seats: 1_000_000, clients: 1_000_000,
      included_credits: 600,
      features: [
        'Assentos ilimitados', 'Clientes ilimitados', 'Tudo da Agência',
        '600 créditos/mês para vídeos, imagens e carrosséis', 'White-label e SSO',
        'Suporte prioritário e onboarding dedicado'
      ]
    }
  ].freeze

  DEFAULT_PACKS = [
    { key: 'starter', name: 'Inicial', price_cents: 5_000,   credits: 50 },
    { key: 'pro',     name: 'Pro',     price_cents: 20_000,  credits: 220 },
    { key: 'studio',  name: 'Studio',  price_cents: 50_000,  credits: 575 },
    { key: 'scale',   name: 'Scale',   price_cents: 100_000, credits: 1_200 }
  ].freeze

  # ── Catalog accessors (admin-configured DB tables, code defaults as fallback) ─

  def plans = PricingPlan.catalog.presence || DEFAULT_PLANS
  def credit_packs = PricingPack.catalog.presence || DEFAULT_PACKS

  def plan(key) = plans.find { |p| p[:key] == key.to_s }
  def credit_pack(key) = credit_packs.find { |p| p[:key] == key.to_s }

  def included_credits_for(plan_key) = plan(plan_key)&.dig(:included_credits) || 0
  def seat_limit_for(plan_key) = plan(plan_key)&.dig(:seats) || 1
  def client_limit_for(plan_key) = plan(plan_key)&.dig(:clients) || 1

  # ── Math accessors (fixed code constants) ─────────────────────────────────

  def trial_days = TRIAL_DAYS
  def credit_unit_cents = CREDIT_UNIT_CENTS
  def usd_brl = USD_BRL.to_f
  def markup = MARKUP.to_f
  def annual_discount_percent = ANNUAL_DISCOUNT_PERCENT

  # The yearly amount (BRL cents): the Stripe-synced value if present, else 12×
  # the monthly price with the annual discount applied.
  def annual_price_cents_for(plan_key)
    p = plan(plan_key) or return 0
    cached = p[:annual_price_cents].to_i
    return cached if cached.positive?

    compute_annual_cents(p[:price_cents])
  end

  def compute_annual_cents(monthly_cents)
    (monthly_cents.to_i * 12 * (100 - annual_discount_percent) / 100.0).round
  end

  # ── Credit cost of a generation ───────────────────────────────────────────
  # Cost-plus: credits track the REAL vendor cost of the operation, converted at
  # a FIXED conservative rate (usd_brl) and marked up (markup). 1 credit = R$1.
  # `credits_for` ESTIMATES the up-front hold (video: per-second USD rate × secs);
  # `credits_for_cost` charges the exact real cost at true-up.
  def credits_for(kind:, seconds: nil)
    case kind.to_s
    when 'image'    then IMAGE_CREDITS
    when 'carousel' then CAROUSEL_CREDITS
    when 'video'
      secs = (seconds || DEFAULT_VIDEO_SECONDS).to_f
      credits_for_cost(cost_cents: VIDEO_USD_PER_SEC * 100.0 * secs)
    else
      0
    end
  end

  # Credits for a KNOWN real vendor cost (USD cents) — the authoritative charge
  # at true-up. revenue = markup × (cost_usd × usd_brl); 1 credit = R$1, so the
  # credit count IS that BRL amount. Rounds up ⇒ realized margin is always ≥ the
  # target (1 − 1/markup). A zero/absent cost charges nothing (callers floor to
  # the estimate so a real render is never billed at 0).
  def credits_for_cost(cost_cents:)
    cents = cost_cents.to_f
    return 0 if cents <= 0

    (cents * usd_brl * markup / 100.0).ceil
  end

  # Public payload for the landing page + in-app plan picker.
  def public_catalog
    {
      trial_days: TRIAL_DAYS,
      credit_unit_cents: CREDIT_UNIT_CENTS,
      annual_discount_percent: ANNUAL_DISCOUNT_PERCENT,
      video_display_seconds: VIDEO_DISPLAY_SECONDS,
      plans: plans.map do |p|
        annual = annual_price_cents_for(p[:key])
        p.slice(:key, :name, :price_cents, :seats, :clients, :included_credits, :features).merge(
          annual_price_cents: annual,
          annual_monthly_equivalent_cents: (annual / 12.0).round
        )
      end,
      credit_packs: credit_packs.map { |p| p.slice(:key, :name, :price_cents, :credits) },
      # Video is cost-based, so its display cost is DERIVED from the same formula
      # the debit uses (an estimate for a VIDEO_DISPLAY_SECONDS clip) — never a
      # stale hand-set number.
      credit_costs: {
        image: IMAGE_CREDITS,
        carousel: CAROUSEL_CREDITS,
        video_15s: credits_for(kind: :video, seconds: VIDEO_DISPLAY_SECONDS)
      }
    }
  end

  # ── Seeding ───────────────────────────────────────────────────────────────
  # Ensure the DB catalog (Subscriptions + Credit Packs) exists, seeded from the
  # code defaults. Idempotent and ADDITIVE — it only creates missing rows, never
  # overwriting an operator's edits or Stripe-synced amounts. Safe to call from
  # db/seeds.rb and admin.
  def seed_defaults!
    DEFAULT_PLANS.each_with_index do |attrs, i|
      existing = PricingPlan.find_by(key: attrs[:key])
      if existing
        # Prod-upgrade backfill: fill a blank annual lookup_key without clobbering
        # any operator/Stripe edits.
        if existing.stripe_annual_lookup_key.blank? && attrs[:stripe_annual_lookup_key].present?
          existing.update!(stripe_annual_lookup_key: attrs[:stripe_annual_lookup_key])
        end
        next
      end

      PricingPlan.create!(attrs.merge(position: i, active: true))
    end

    DEFAULT_PACKS.each_with_index do |attrs, i|
      next if PricingPack.exists?(key: attrs[:key])

      PricingPack.create!(attrs.merge(position: i, active: true))
    end
  end
end
