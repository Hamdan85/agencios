# frozen_string_literal: true

# Godfathered (comped) workspaces get unlimited access, but staff can optionally
# cap how many generation credits they burn per month. `monthly_credit_limit` is
# that cap (in credits); NULL = unlimited (the historical behaviour). Only
# meaningful for godfathered workspaces — everyone else is driven by their plan.
class AddMonthlyCreditLimitToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :monthly_credit_limit, :integer, null: true
  end
end
