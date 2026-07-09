# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pricing, type: :model do
  describe 'DB-backed, no-deploy config' do
    it 'falls back to code defaults when the tables are empty' do
      PricingPlan.delete_all
      PricingPack.delete_all
      expect(Pricing.plans.map { |p| p[:key] }).to eq(%w[solo agencia enterprise])
      expect(Pricing.credit_packs.size).to eq(Pricing::DEFAULT_PACKS.size)
    end

    it 'reflects an admin edit to a plan price immediately (no deploy)' do
      Pricing.seed_defaults!
      PricingPlan.find_by(key: 'solo').update!(price_cents: 12_900, included_credits: 60)

      solo = Pricing.plan('solo')
      expect(solo[:price_cents]).to eq(12_900)
      expect(Pricing.included_credits_for('solo')).to eq(60)
      expect(Controllers::Billing::Plans.find('solo')[:price_cents]).to eq(12_900)
    end

    it 'charges the fixed code-constant credit cost per generation kind' do
      expect(Pricing.credits_for(kind: :image)).to eq(Pricing::IMAGE_CREDITS)
      expect(Pricing.credits_for(kind: :carousel)).to eq(Pricing::CAROUSEL_CREDITS)
    end

    it 'exposes the trial length as a fixed code constant' do
      expect(Pricing.trial_days).to eq(Pricing::TRIAL_DAYS)
    end

    it 'computes the annual price as 12× monthly minus the fixed discount' do
      Pricing.seed_defaults!
      PricingPlan.find_by(key: 'solo').update!(price_cents: 9_900, annual_price_cents: 0)

      # 9900 * 12 * 0.85 = 100_980 (ANNUAL_DISCOUNT_PERCENT = 15)
      expect(Pricing.annual_price_cents_for('solo')).to eq(100_980)
    end

    it 'prefers a Stripe-synced annual amount over the computed default' do
      Pricing.seed_defaults!
      PricingPlan.find_by(key: 'solo').update!(price_cents: 9_900, annual_price_cents: 95_000)
      expect(Pricing.annual_price_cents_for('solo')).to eq(95_000)
    end

    it 'exposes annual price + discount in the public catalog' do
      Pricing.seed_defaults!
      cat = Pricing.public_catalog
      expect(cat[:annual_discount_percent]).to eq(15)
      solo = cat[:plans].find { |p| p[:key] == 'solo' }
      expect(solo[:annual_price_cents]).to be_positive
      expect(solo[:annual_monthly_equivalent_cents]).to eq((solo[:annual_price_cents] / 12.0).round)
    end

    it 'seed_defaults! is additive and does not clobber edits' do
      Pricing.seed_defaults!
      PricingPlan.find_by(key: 'solo').update!(price_cents: 15_000)
      Pricing.seed_defaults! # run again
      expect(PricingPlan.find_by(key: 'solo').price_cents).to eq(15_000)
    end
  end

  # The credit charge tracks the REAL vendor cost of each operation (cost-plus),
  # not the video's final duration. The dollar is passed through via a FIXED,
  # conservative internal rate (USD_BRL) + a markup (MARKUP), so every operation
  # clears the target margin. These are fixed code constants (Pricing::USD_BRL =
  # 6.00, MARKUP = 6.5, VIDEO_USD_PER_SEC = 0.16). See docs/pricing-model.md.
  describe 'cost-based credit pricing' do
    it 'charges credits = ceil(cost_usd_cents × usd_brl × markup ÷ 100) for a real cost' do
      # 8s clip real cost $1.28 = 128 USD cents → ceil(128 × 6.00 × 6.5 ÷ 100) = 50
      expect(Pricing.credits_for_cost(cost_cents: 128)).to eq(50)
      # image real cost $0.04 = 4 USD cents → ceil(4 × 6.00 × 6.5 ÷ 100) = 2
      expect(Pricing.credits_for_cost(cost_cents: 4)).to eq(2)
    end

    it 'guarantees ≥80% margin on the charge (rounds up, never down)' do
      [4, 37, 64, 128, 200].each do |cost_cents|
        credits    = Pricing.credits_for_cost(cost_cents: cost_cents)
        revenue_br = credits * 1.0                          # 1 credit = R$1 nominal
        cost_br    = cost_cents / 100.0 * 6.00              # USD → BRL at the internal rate
        margin     = (revenue_br - cost_br) / revenue_br
        expect(margin).to be >= 0.80
      end
    end

    it 'charges nothing for a zero real cost' do
      expect(Pricing.credits_for_cost(cost_cents: 0)).to eq(0)
    end

    it 'estimates a video HOLD from the per-second USD cost rate' do
      # 8s × $0.16/s = $1.28 = 128 USD cents → same 50 credits as the real 8s clip
      expect(Pricing.credits_for(kind: :video, seconds: 8)).to eq(50)
      # 4s × $0.16/s = $0.64 = 64 USD cents → ceil(64 × 6 × 6.5 ÷ 100) = 25
      expect(Pricing.credits_for(kind: :video, seconds: 4)).to eq(25)
    end

    it 'keeps image at the flat image_credits (cheap, stable operation)' do
      expect(Pricing.credits_for(kind: :image)).to eq(1)
    end
  end
end
