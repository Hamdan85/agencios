# frozen_string_literal: true

# Stripe usage-metering was removed in favour of prepaid credits, so `metered_at`
# is written nowhere and always nil. Drop it. The real vendor cost stays in
# `generations.cost_cents` + the AiUsageLog trail. Reversible.
class DropMeteredAtFromGenerations < ActiveRecord::Migration[8.1]
  def up
    remove_column :generations, :metered_at
  end

  def down
    add_column :generations, :metered_at, :datetime
  end
end
