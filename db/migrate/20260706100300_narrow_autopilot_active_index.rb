# frozen_string_literal: true

# 'publishing' is no longer an active ticket-run state (GO stops at production),
# so the one-active-per-ticket partial index must drop it to stay in sync.
class NarrowAutopilotActiveIndex < ActiveRecord::Migration[8.1]
  def up
    remove_index :autopilot_runs, name: 'index_autopilot_runs_one_active_per_ticket'
    add_index :autopilot_runs, :ticket_id, unique: true,
              where: "scope = 'ticket' AND state IN ('pending','scoping','generating','awaiting_generation')",
              name: 'index_autopilot_runs_one_active_per_ticket'
  end

  def down
    remove_index :autopilot_runs, name: 'index_autopilot_runs_one_active_per_ticket'
    add_index :autopilot_runs, :ticket_id, unique: true,
              where: "scope = 'ticket' AND state IN ('pending','scoping','generating','awaiting_generation','publishing')",
              name: 'index_autopilot_runs_one_active_per_ticket'
  end
end
