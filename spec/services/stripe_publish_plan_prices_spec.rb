# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vendors::Stripe::Actions::PublishPlanPrices do
  let(:client) do
    Class.new do
      attr_reader :created, :archived

      def initialize
        @created = []
        @archived = []
        @seq = 0
      end

      def create_product(**) = Struct.new(:id).new('prod_1')

      def create_price(unit_amount:, lookup_key:, interval:, product:)
        @seq += 1
        @created << { unit_amount: unit_amount, lookup_key: lookup_key, interval: interval }
        Struct.new(:id, :unit_amount, :product).new("price_#{@seq}", unit_amount, product)
      end

      def deactivate_price(id) = @archived << id
    end.new
  end

  before { Pricing.seed_defaults! }

  it "creates a new monthly + annual Price with the plan's lookup_keys and caches ids back" do
    plan = PricingPlan.find_by(key: 'solo')
    plan.update!(price_cents: 12_900, annual_price_cents: 0, stripe_price_id: nil, stripe_annual_price_id: nil)

    result = described_class.call(plan: plan, client: client)

    expect(client.created.map { |c| c[:interval] }).to contain_exactly('month', 'year')
    monthly = client.created.find { |c| c[:interval] == 'month' }
    annual  = client.created.find { |c| c[:interval] == 'year' }
    expect(monthly).to include(unit_amount: 12_900, lookup_key: 'solo_monthly')
    expect(annual[:lookup_key]).to eq('solo_yearly')
    expect(annual[:unit_amount]).to eq(Pricing.annual_price_cents_for('solo')) # 12900*12*0.85

    plan.reload
    expect(plan.stripe_price_id).to be_present
    expect(plan.stripe_annual_price_id).to be_present
    expect(result.first[:key]).to eq('solo')
  end

  it 'archives the superseded Prices' do
    plan = PricingPlan.find_by(key: 'solo')
    plan.update!(stripe_price_id: 'price_old_m', stripe_annual_price_id: 'price_old_y')

    described_class.call(plan: plan, client: client)

    expect(client.archived).to contain_exactly('price_old_m', 'price_old_y')
  end
end
