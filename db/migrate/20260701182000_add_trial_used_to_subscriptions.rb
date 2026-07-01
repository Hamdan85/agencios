# frozen_string_literal: true

class AddTrialUsedToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # Whether this workspace has already consumed its free trial. The trial is
    # granted only on the FIRST checkout — later checkouts (re-subscribe, plan
    # change via checkout) do not re-grant it.
    add_column :subscriptions, :trial_used, :boolean, null: false, default: false
  end
end
