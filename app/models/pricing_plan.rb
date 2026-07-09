# frozen_string_literal: true

# A SaaS plan in the catalog (admin-editable). `price_cents` is the SOURCE OF
# TRUTH for the price: saving a plan in /admin pushes it to Stripe (mints the
# recurring Price) via Operations::Billing::SyncPlanToStripe. SyncPlanPrices can
# also pull an amount changed directly in the Stripe Dashboard back into the row.
class PricingPlan < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :price_cents, :seats, :clients, :included_credits,
            numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position, :id) }
  scope :active_only, -> { where(active: true) }

  # The catalog as an array of config hashes (or [] when empty ⇒ Pricing falls
  # back to code defaults).
  def self.catalog
    active_only.ordered.map(&:to_config_h)
  end

  def to_config_h
    {
      key: key, name: name, price_cents: price_cents,
      annual_price_cents: annual_price_cents, seats: seats, clients: clients,
      included_credits: included_credits, features: Array(features),
      stripe_lookup_key: stripe_lookup_key, stripe_annual_lookup_key: stripe_annual_lookup_key
    }
  end

  # Edit the features array as newline-separated text in the admin form.
  def features_text = Array(features).join("\n")

  def features_text=(value)
    self.features = value.to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
  end

  def self.ransackable_attributes(_auth = nil)
    %w[id key name stripe_product_id stripe_lookup_key stripe_price_id
       stripe_annual_lookup_key stripe_annual_price_id price_cents annual_price_cents
       seats clients included_credits position active created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil) = []
end
