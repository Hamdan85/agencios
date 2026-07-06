# frozen_string_literal: true

# Facade over the pricing catalog. Everything money-facing resolves here so the
# landing page, in-app billing, Stripe checkout, and the credit-debit path all
# agree.
#
# Source of truth:
#   * The *charged* subscription amount lives in STRIPE (Product + Price, resolved
#     by lookup_key). Changing a plan price is a Stripe Dashboard operation — no
#     deploy — and SyncPlanPrices caches the amount back into `pricing_plans`.
#   * The commercial knobs (trial length, credit costs, included credits, packs,
#     plan metadata) live in DB tables (PricingConfig/PricingPlan/PricingPack),
#     editable from ActiveAdmin — no deploy.
#
# The DEFAULT_* constants below are the SEED for those tables and the fallback
# used before they're seeded, so a fresh install works out of the box.
#
# Margin model: a credit is worth `credit_unit_cents` at retail and a generation
# is charged at ~`margin_multiplier`× vendor cost (≈80% gross margin).
module Pricing
  module_function

  # Technical (non-commercial) constants — not admin-tunable.
  PHOTOREAL_ENGINES = %w[avatar_iv avatar_iii].freeze
  DEFAULT_VIDEO_SECONDS = 30
  CREDIT_PACK_TTL = 12.months

  # ── Seed / fallback defaults ──────────────────────────────────────────────
  DEFAULT_CONFIG = {
    trial_days: 7, annual_discount_percent: 15, credit_unit_cents: 100,
    margin_multiplier: 6.5, usd_brl: 6.00, video_usd_per_sec: 0.16,
    image_credits: 1, carousel_credits: 0,
    # deprecated — video is cost-based now (see credits_for); kept for the admin form
    video_standard_credits_per_15s: 8, video_photoreal_credits_per_15s: 30
  }.freeze

  DEFAULT_PLANS = [
    {
      key: 'solo', name: 'Solo', stripe_lookup_key: 'solo_monthly', stripe_annual_lookup_key: 'solo_yearly',
      price_cents: 9_900, usd_cents: 1_900, seats: 2, clients: 3, included_credits: 40,
      features: [
        '2 assentos', 'Até 3 clientes', 'Quadro de produção completo',
        'Carrosséis e legendas com IA inclusos',
        '40 créditos/mês para vídeos e imagens', 'Integrações sociais diretas'
      ]
    },
    {
      key: 'agencia', name: 'Agência', stripe_lookup_key: 'agencia_monthly', stripe_annual_lookup_key: 'agencia_yearly',
      price_cents: 34_900, usd_cents: 7_900, seats: 20, clients: 25, included_credits: 200,
      features: [
        'Até 20 assentos', 'Até 25 clientes', 'Tudo do Solo',
        '200 créditos/mês para vídeos e imagens',
        'Faturamento de clientes (Mercado Pago)', 'Calendário e reuniões (Google)',
        'Aprovações de cliente e relatórios com IA'
      ]
    },
    {
      key: 'enterprise', name: 'Enterprise', stripe_lookup_key: 'enterprise_monthly', stripe_annual_lookup_key: 'enterprise_yearly',
      price_cents: 99_900, usd_cents: 24_900, seats: 1_000_000, clients: 1_000_000,
      included_credits: 600,
      features: [
        'Assentos ilimitados', 'Clientes ilimitados', 'Tudo da Agência',
        '600 créditos/mês para vídeos e imagens', 'White-label e SSO',
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

  # ── Config accessors (DB, falling back to code defaults) ──────────────────

  def config = PricingConfig.instance

  def plans = PricingPlan.catalog.presence || DEFAULT_PLANS
  def credit_packs = PricingPack.catalog.presence || DEFAULT_PACKS

  def plan(key) = plans.find { |p| p[:key] == key.to_s }
  def credit_pack(key) = credit_packs.find { |p| p[:key] == key.to_s }

  def included_credits_for(plan_key) = plan(plan_key)&.dig(:included_credits) || 0
  def seat_limit_for(plan_key) = plan(plan_key)&.dig(:seats) || 1
  def client_limit_for(plan_key) = plan(plan_key)&.dig(:clients) || 1

  def trial_days = config.trial_days
  def credit_unit_cents = config.credit_unit_cents
  def usd_brl = config.usd_brl.to_f
  def markup = config.margin_multiplier.to_f
  def annual_discount_percent = config.annual_discount_percent

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

  # Resolve the Stripe lookup_key for a plan + billing interval.
  def lookup_key_for(plan_key, interval)
    p = plan(plan_key) or return nil
    interval.to_s == 'year' ? p[:stripe_annual_lookup_key] : p[:stripe_lookup_key]
  end

  # ── Credit cost of a generation ───────────────────────────────────────────
  # Cost-plus: credits track the REAL vendor cost of the operation, converted at
  # a FIXED conservative rate (usd_brl) and marked up (markup). 1 credit = R$1.
  # `credits_for` ESTIMATES the up-front hold (video: per-second USD rate × secs);
  # `credits_for_cost` charges the exact real cost at true-up.
  def credits_for(kind:, seconds: nil, engine: nil)
    c = config
    case kind.to_s
    when 'image'    then c.image_credits
    when 'carousel' then c.carousel_credits
    when 'video'
      secs = (seconds || DEFAULT_VIDEO_SECONDS).to_f
      credits_for_cost(cost_cents: c.video_usd_per_sec.to_f * 100.0 * secs)
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

  def photoreal_engine?(engine) = PHOTOREAL_ENGINES.include?(engine.to_s)

  # Public payload for the landing page + in-app plan picker.
  def public_catalog
    c = config
    {
      trial_days: c.trial_days,
      credit_unit_cents: c.credit_unit_cents,
      annual_discount_percent: c.annual_discount_percent,
      plans: plans.map do |p|
        annual = annual_price_cents_for(p[:key])
        p.slice(:key, :name, :price_cents, :usd_cents, :seats, :clients, :included_credits, :features).merge(
          annual_price_cents: annual,
          annual_monthly_equivalent_cents: (annual / 12.0).round
        )
      end,
      credit_packs: credit_packs.map { |p| p.slice(:key, :name, :price_cents, :credits) },
      credit_costs: {
        image: c.image_credits, carousel: c.carousel_credits,
        video_standard_15s: c.video_standard_credits_per_15s,
        video_photoreal_15s: c.video_photoreal_credits_per_15s
      }
    }
  end

  # ── Seeding ───────────────────────────────────────────────────────────────
  # Ensure the DB catalog exists, seeded from the code defaults. Idempotent and
  # ADDITIVE — it only creates missing rows, never overwriting an operator's
  # edits or Stripe-synced amounts. Safe to call from db/seeds.rb and admin.
  def seed_defaults!
    PricingConfig.first_or_create!

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
