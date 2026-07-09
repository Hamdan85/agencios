# frozen_string_literal: true

require 'rails_helper'

# The admin is the source of truth for a plan's price: saving it syncs Stripe.
# Unlike a blind "publish", this sync is IDEMPOTENT — it mints a new Price only
# when the amount actually changed, so a plain edit (name/features) is a no-op.
RSpec.describe Operations::Billing::SyncPlanToStripe do
  # Minimal fakes of the Stripe objects the sync inspects.
  StripeRecurring = Struct.new(:interval)
  StripePrice = Struct.new(:id, :active, :unit_amount, :recurring)

  let(:client) do
    Class.new do
      attr_reader :created, :archived, :product_updates
      attr_accessor :store # price_id => StripePrice

      def initialize
        @created = []
        @archived = []
        @product_updates = []
        @store = {}
        @seq = 0
      end

      def create_product(**) = Struct.new(:id).new('prod_1')
      def update_product(id, name:, active:) = (@product_updates << { id: id, name: name, active: active })

      def create_price(unit_amount:, lookup_key:, interval:, product:)
        @seq += 1
        id = "price_#{@seq}"
        @created << { unit_amount: unit_amount, lookup_key: lookup_key, interval: interval }
        @store[id] = StripePrice.new(id, true, unit_amount, StripeRecurring.new(interval))
        Struct.new(:id, :unit_amount, :product).new(id, unit_amount, product)
      end

      def retrieve_price(id)
        @store[id] || raise(Vendors::Stripe::Client::Error, 'No such price')
      end

      def deactivate_price(id)
        @archived << id
        @store[id]&.active = false
      end
    end.new
  end

  before { Pricing.seed_defaults! }

  it 'creates a Product + monthly & annual Prices for an unsynced plan and caches ids' do
    plan = PricingPlan.find_by(key: 'solo')
    plan.update!(price_cents: 12_900, annual_price_cents: 0, stripe_product_id: nil,
                 stripe_price_id: nil, stripe_annual_price_id: nil)

    described_class.call(plan: plan, client: client)

    expect(client.created.map { |c| c[:interval] }).to contain_exactly('month', 'year')
    monthly = client.created.find { |c| c[:interval] == 'month' }
    expect(monthly).to include(unit_amount: 12_900, lookup_key: 'solo_monthly')

    plan.reload
    expect(plan.stripe_product_id).to eq('prod_1')
    expect(plan.stripe_price_id).to be_present
    expect(plan.stripe_annual_price_id).to be_present
  end

  it 'is a no-op (mints no new Price) when the amounts already match Stripe' do
    plan = PricingPlan.find_by(key: 'solo')
    plan.update!(price_cents: 12_900, annual_price_cents: 0, stripe_product_id: 'prod_1')
    described_class.call(plan: plan, client: client) # first sync creates them
    client.created.clear

    described_class.call(plan: plan.reload, client: client) # second sync — nothing changed

    expect(client.created).to be_empty
    expect(client.archived).to be_empty
    expect(client.product_updates).not_to be_empty # product name still upserted
  end

  it 'mints a new Price and archives the old one when the monthly amount changes' do
    plan = PricingPlan.find_by(key: 'solo')
    plan.update!(price_cents: 9_900, annual_price_cents: 5_000, stripe_product_id: 'prod_1')
    described_class.call(plan: plan, client: client)
    old_monthly_id = plan.reload.stripe_price_id
    client.created.clear

    plan.update!(price_cents: 14_900) # admin raises the monthly price
    described_class.call(plan: plan.reload, client: client)

    expect(client.created.map { |c| c[:interval] }).to eq(['month']) # only the changed interval
    expect(client.created.first[:unit_amount]).to eq(14_900)
    expect(client.archived).to include(old_monthly_id)
    expect(plan.reload.stripe_price_id).not_to eq(old_monthly_id)
  end
end
