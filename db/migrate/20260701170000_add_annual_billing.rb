# frozen_string_literal: true

class AddAnnualBilling < ActiveRecord::Migration[8.1]
  def change
    # Annual billing: a configurable discount vs. 12× the monthly price.
    add_column :pricing_configs, :annual_discount_percent, :integer, null: false, default: 15

    # Each plan gets a second (yearly) Stripe Price alongside the monthly one.
    # annual_price_cents is the cached/display yearly amount (from Stripe, or the
    # computed default 12× monthly × (1 - discount)).
    add_column :pricing_plans, :stripe_annual_lookup_key, :string
    add_column :pricing_plans, :stripe_annual_price_id, :string
    add_column :pricing_plans, :annual_price_cents, :integer, null: false, default: 0
  end
end
