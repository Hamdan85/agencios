# frozen_string_literal: true

# The strategist conversation becomes ONE per project, forever — applying or
# discarding a plan no longer retires the session, so the chat keeps its full
# memory. This migration consolidates the historical many-sessions-per-project
# data into that shape:
#
#   1. Per project, the most recent session becomes the canonical one; the older
#      sessions' transcripts are merged into it (chronologically) so no memory is
#      lost, their tickets are re-pointed to it, and they are deleted.
#   2. Stale DESTRUCTIVE proposals are neutralized: a `proposed` session holding a
#      full (non-append) plan on a project that already has tickets would, on
#      apply, discard the whole existing batch — those are reset to `active` with
#      the plan cleared (the router now refuses to produce them; this clears the
#      ones already stored).
#   3. Legacy `applied` / `discarded` statuses fold back into `active` — the
#      session is eternal; only `proposed` (a plan awaiting decision) matters.
#   4. A unique index on project_id enforces one-session-per-project from now on.
class ConsolidateStrategySessionsPerProject < ActiveRecord::Migration[8.1]
  # Lightweight AR handles so the migration never couples to app models.
  class MigSession < ActiveRecord::Base
    self.table_name = 'strategy_sessions'
  end

  class MigTicket < ActiveRecord::Base
    self.table_name = 'tickets'
  end

  def up
    consolidate_duplicates
    neutralize_stale_destructive_plans
    fold_legacy_statuses
    add_index :strategy_sessions, :project_id, unique: true,
              name: 'index_strategy_sessions_one_per_project'
  end

  def down
    remove_index :strategy_sessions, name: 'index_strategy_sessions_one_per_project'
    # The transcript merge / deletions are irreversible by nature; the index
    # removal restores the many-sessions capability.
  end

  private

  def consolidate_duplicates
    duplicated_project_ids = MigSession.group(:project_id).having('COUNT(*) > 1').pluck(:project_id)
    duplicated_project_ids.each do |project_id|
      sessions = MigSession.where(project_id: project_id).order(:created_at).to_a
      canonical = sessions.pop # newest wins; older ones fold into it

      merged = sessions.flat_map { |s| Array(s.messages) } + Array(canonical.messages)
      canonical.update_columns(messages: merged, updated_at: Time.current)

      older_ids = sessions.map(&:id)
      MigTicket.where(strategy_session_id: older_ids).update_all(strategy_session_id: canonical.id)
      MigSession.where(id: older_ids).delete_all
    end
  end

  def neutralize_stale_destructive_plans
    MigSession.where(status: 'proposed').find_each do |session|
      plan = session.proposed_plan
      next unless plan.is_a?(Hash) && plan['mode'] != 'append'
      next unless MigTicket.where(project_id: session.project_id).exists?

      session.update_columns(status: 'active', proposed_plan: {}, updated_at: Time.current)
    end
  end

  def fold_legacy_statuses
    MigSession.where(status: 'discarded').update_all(status: 'active', proposed_plan: {})
    MigSession.where(status: 'applied').update_all(status: 'active')
  end
end
