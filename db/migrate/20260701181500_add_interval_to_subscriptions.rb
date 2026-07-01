# frozen_string_literal: true

class AddIntervalToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # The active billing cycle of the subscription ("month" | "year"), synced from
    # the Stripe price's recurring.interval. Lets the UI tell monthly vs. annual
    # apart so the user can switch between them.
    add_column :subscriptions, :interval, :string, null: false, default: "month"
  end
end
