# frozen_string_literal: true

# Links a ticket to the strategy-planner session that created it, so re-applying
# an edited plan can rewrite from scratch (delete the prior batch, recreate)
# instead of duplicating. Nullify on session delete — the tickets outlive it.
class AddStrategySessionToTickets < ActiveRecord::Migration[8.1]
  def change
    add_reference :tickets, :strategy_session, null: true, index: true,
                  foreign_key: { on_delete: :nullify }
  end
end
