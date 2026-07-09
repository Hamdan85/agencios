# frozen_string_literal: true

# The credit-economy knobs (markup, FX, per-op credit costs, trial length) are
# now fixed code constants in `Pricing` — not admin-tunable. Admin configures ONLY
# Subscriptions (pricing_plans) and Credit Packs (pricing_packs). Drop the orphaned
# singleton config table. Reversible: `down` recreates it with the prior schema.
class DropPricingConfigs < ActiveRecord::Migration[8.1]
  def up
    drop_table :pricing_configs
  end

  def down
    create_table :pricing_configs do |t|
      t.integer :trial_days, default: 7, null: false
      t.integer :annual_discount_percent, default: 15, null: false
      t.integer :credit_unit_cents, default: 100, null: false
      t.decimal :margin_multiplier, precision: 5, scale: 2, default: '6.5', null: false
      t.decimal :usd_brl, precision: 8, scale: 4, default: '6.0', null: false
      t.decimal :video_usd_per_sec, precision: 6, scale: 4, default: '0.16', null: false
      t.integer :image_credits, default: 1, null: false
      t.integer :carousel_credits, default: 1, null: false
      t.integer :video_standard_credits_per_15s, default: 8, null: false
      t.integer :video_photoreal_credits_per_15s, default: 30, null: false
      t.timestamps
    end
  end
end
