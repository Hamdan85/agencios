# frozen_string_literal: true

# A prepaid credit pack in the catalog (admin-editable). Sold via a one-time
# Stripe Checkout using inline `price_data` (the amount is server-derived from
# this row), so pack prices change with no Stripe Price object and no deploy.
class PricingPack < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :price_cents, :credits, numericality: { greater_than: 0 }

  scope :ordered, -> { order(:position, :id) }
  scope :active_only, -> { where(active: true) }

  def self.catalog
    active_only.ordered.map(&:to_config_h)
  end

  def to_config_h
    { key: key, name: name, price_cents: price_cents, credits: credits }
  end

  def self.ransackable_attributes(_auth = nil)
    %w[id key name price_cents credits position active created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil) = []
end
