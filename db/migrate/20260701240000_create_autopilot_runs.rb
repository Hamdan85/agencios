# frozen_string_literal: true

# Autopilot ("GO mode"): a resumable run that walks an eligible ticket through
# the funnel on its own — filling fields, generating every creative, and
# scheduling the posts. One row per ticket per GO; a project/batch GO adds a
# `scope: batch` coordinator row that its child ticket-runs point at via
# `batch_id`.
class CreateAutopilotRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :autopilot_runs do |t|
      t.references :workspace, null: false, foreign_key: true, index: true
      # A coordinator (scope: batch) has no ticket; a ticket-run always does.
      t.references :ticket, foreign_key: true, index: true
      t.references :user, foreign_key: true
      # Self-FK to the batch coordinator row (nil for a standalone per-ticket GO).
      t.bigint  :batch_id, index: true

      t.string  :scope, null: false, default: 'ticket' # ticket | batch
      t.string  :state, null: false, default: 'pending'
      t.string  :target_status, null: false, default: 'scheduled'
      t.string  :mode, null: false, default: 'scheduled' # immediate | scheduled
      t.datetime :scheduled_at

      t.integer :estimated_credits, null: false, default: 0
      t.integer :spent_credits, null: false, default: 0

      t.jsonb   :progress, null: false, default: {}
      t.string  :failure_reason
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :autopilot_runs, %i[workspace_id state]
    add_index :autopilot_runs, %i[ticket_id state]

    # At most one ACTIVE run per ticket — the GO button is idempotent, and a
    # second concurrent press must not spawn a parallel run.
    add_index :autopilot_runs, :ticket_id, unique: true,
              where: "scope = 'ticket' AND state IN " \
                     "('pending','scoping','generating','awaiting_generation','publishing')",
              name: 'index_autopilot_runs_one_active_per_ticket'
  end
end
