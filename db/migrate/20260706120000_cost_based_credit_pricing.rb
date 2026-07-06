# frozen_string_literal: true

# Move video billing from "credits per 15s" to cost-plus per operation:
#   * margin_multiplier becomes decimal (needs 6.5× to clear 80% net after the
#     worst pack discount + IOF + gateway).
#   * video_usd_per_sec is the conservative per-second vendor cost (USD) used to
#     ESTIMATE the up-front hold; the real cost trues it up at finalize.
# See docs/pricing-model.md. The old video_*_credits_per_15s columns are kept
# (deprecated) to avoid breaking the admin form; they are no longer read.
class CostBasedCreditPricing < ActiveRecord::Migration[8.1]
  def up
    change_column :pricing_configs, :margin_multiplier, :decimal,
                  precision: 5, scale: 2, default: 6.5, null: false
    add_column :pricing_configs, :video_usd_per_sec, :decimal,
               precision: 6, scale: 4, default: 0.16, null: false
  end

  def down
    remove_column :pricing_configs, :video_usd_per_sec
    change_column :pricing_configs, :margin_multiplier, :integer, default: 5, null: false
  end
end
