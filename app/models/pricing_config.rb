# frozen_string_literal: true

# Singleton row holding the credit-economy + trial knobs (admin-editable).
# Read through the `Pricing` facade. `instance` returns the row, or an unsaved
# defaults-populated record when the table is empty (fresh install) so reads
# never write.
class PricingConfig < ApplicationRecord
  validates :trial_days, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 90 }
  validates :annual_discount_percent, numericality: { greater_than_or_equal_to: 0, less_than: 100 }
  validates :credit_unit_cents, :margin_multiplier, :usd_brl, :video_usd_per_sec,
            :image_credits, :carousel_credits,
            :video_standard_credits_per_15s, :video_photoreal_credits_per_15s,
            numericality: { greater_than_or_equal_to: 0 }

  def self.instance
    first || new
  end

  def self.ransackable_attributes(_auth = nil)
    %w[id trial_days annual_discount_percent credit_unit_cents margin_multiplier usd_brl
       video_usd_per_sec image_credits carousel_credits
       video_standard_credits_per_15s video_photoreal_credits_per_15s]
  end

  def self.ransackable_associations(_auth = nil) = []
end
