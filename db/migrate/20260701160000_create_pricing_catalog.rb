# frozen_string_literal: true

# Move the commercial knobs out of code into DB-backed, admin-editable config, so
# pricing changes are operational (no deploy). Stripe stays the source of truth
# for the *charged* amount (resolved by Product/lookup_key); these tables carry
# the display + credit-economy knobs and cache the Stripe amount.
class CreatePricingCatalog < ActiveRecord::Migration[8.1]
  def change
    # Singleton row: the credit economy + trial knobs.
    create_table :pricing_configs do |t|
      t.integer :trial_days, null: false, default: 7
      t.integer :credit_unit_cents, null: false, default: 100  # 1 credit = R$1,00
      t.integer :margin_multiplier, null: false, default: 5     # 5× cost ⇒ 80% margin (display)
      t.decimal :usd_brl, precision: 8, scale: 4, null: false, default: "5.40"
      t.integer :image_credits, null: false, default: 1
      t.integer :carousel_credits, null: false, default: 0
      t.integer :video_standard_credits_per_15s, null: false, default: 8
      t.integer :video_photoreal_credits_per_15s, null: false, default: 30
      t.timestamps
    end

    create_table :pricing_plans do |t|
      t.string  :key, null: false
      t.string  :name, null: false
      # Stripe pointers: product is the STABLE identity of the plan (survives price
      # changes / grandfathering); lookup_key points at the current price;
      # price_id + price_cents are cached from Stripe by SyncPlanPrices.
      t.string  :stripe_product_id
      t.string  :stripe_lookup_key
      t.string  :stripe_price_id
      t.integer :price_cents, null: false, default: 0   # BRL, cached/display
      t.integer :usd_cents, null: false, default: 0
      t.integer :seats, null: false, default: 1
      t.integer :clients, null: false, default: 1
      t.integer :included_credits, null: false, default: 0
      t.jsonb   :features, null: false, default: []
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :pricing_plans, :key, unique: true

    create_table :pricing_packs do |t|
      t.string  :key, null: false
      t.string  :name, null: false
      t.integer :price_cents, null: false, default: 0   # BRL
      t.integer :credits, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :pricing_packs, :key, unique: true
  end
end
