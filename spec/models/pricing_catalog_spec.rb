# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pricing, type: :model do
  describe "DB-backed, no-deploy config" do
    it "falls back to code defaults when the tables are empty" do
      PricingPlan.delete_all
      PricingPack.delete_all
      expect(Pricing.plans.map { |p| p[:key] }).to eq(%w[solo agencia enterprise])
      expect(Pricing.credit_packs.size).to eq(Pricing::DEFAULT_PACKS.size)
    end

    it "reflects an admin edit to a plan price immediately (no deploy)" do
      Pricing.seed_defaults!
      PricingPlan.find_by(key: "solo").update!(price_cents: 12_900, included_credits: 60)

      solo = Pricing.plan("solo")
      expect(solo[:price_cents]).to eq(12_900)
      expect(Pricing.included_credits_for("solo")).to eq(60)
      expect(Controllers::Billing::Plans.find("solo")[:price_cents]).to eq(12_900)
    end

    it "reflects an admin edit to the credit-cost config immediately" do
      cfg = PricingConfig.first_or_create!
      cfg.update!(image_credits: 3, video_standard_credits_per_15s: 10)

      expect(Pricing.credits_for(kind: :image)).to eq(3)
      expect(Pricing.credits_for(kind: :video, seconds: 30)).to eq(20) # 10/15*30
    end

    it "reflects a trial-length change from config" do
      PricingConfig.first_or_create!.update!(trial_days: 14)
      expect(Pricing.trial_days).to eq(14)
    end

    it "computes the annual price as 12× monthly minus the configured discount" do
      Pricing.seed_defaults!
      PricingConfig.first_or_create!.update!(annual_discount_percent: 15)
      PricingPlan.find_by(key: "solo").update!(price_cents: 9_900, annual_price_cents: 0)

      # 9900 * 12 * 0.85 = 100_980
      expect(Pricing.annual_price_cents_for("solo")).to eq(100_980)
    end

    it "prefers a Stripe-synced annual amount over the computed default" do
      Pricing.seed_defaults!
      PricingPlan.find_by(key: "solo").update!(price_cents: 9_900, annual_price_cents: 95_000)
      expect(Pricing.annual_price_cents_for("solo")).to eq(95_000)
    end

    it "exposes annual price + discount in the public catalog" do
      Pricing.seed_defaults!
      cat = Pricing.public_catalog
      expect(cat[:annual_discount_percent]).to eq(15)
      solo = cat[:plans].find { |p| p[:key] == "solo" }
      expect(solo[:annual_price_cents]).to be_positive
      expect(solo[:annual_monthly_equivalent_cents]).to eq((solo[:annual_price_cents] / 12.0).round)
    end

    it "resolves the annual lookup_key for a plan+interval" do
      Pricing.seed_defaults!
      expect(Pricing.lookup_key_for("solo", "year")).to eq("solo_yearly")
      expect(Pricing.lookup_key_for("solo", "month")).to eq("solo_monthly")
    end

    it "seed_defaults! is additive and does not clobber edits" do
      Pricing.seed_defaults!
      PricingPlan.find_by(key: "solo").update!(price_cents: 15_000)
      Pricing.seed_defaults! # run again
      expect(PricingPlan.find_by(key: "solo").price_cents).to eq(15_000)
    end
  end
end
