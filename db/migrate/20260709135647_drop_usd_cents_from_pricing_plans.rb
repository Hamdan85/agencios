# frozen_string_literal: true

# `usd_cents` was a "USD display" price that was never actually displayed anywhere
# (all money is shown in BRL from price_cents). Drop the unused column. Reversible.
class DropUsdCentsFromPricingPlans < ActiveRecord::Migration[8.1]
  def up
    remove_column :pricing_plans, :usd_cents
  end

  def down
    add_column :pricing_plans, :usd_cents, :integer, default: 0, null: false
  end
end
