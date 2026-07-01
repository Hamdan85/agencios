# frozen_string_literal: true

module Operations
  module Autopilot
    # Rolls a batch coordinator to a terminal state once all of its child
    # ticket-runs have finished. Called whenever a child run completes or fails.
    class RecomputeBatch < Operations::Base
      def initialize(batch_id:)
        @batch_id = batch_id
      end

      def call
        batch = AutopilotRun.batches.find_by(id: @batch_id)
        return if batch.nil? || batch.terminal?

        children = AutopilotRun.ticket_runs.where(batch_id: batch.id).to_a
        return if children.empty? || children.any?(&:active?)

        failed = children.count { |c| c.state == 'failed' }
        state = failed.zero? ? 'completed' : 'completed_with_failures'
        batch.update!(state: state, finished_at: Time.current)
        Broadcaster.board(batch.workspace_id, 'autopilot_batch_completed',
                          batch_id: batch.id, state: state, failed: failed, total: children.size)
        batch
      end
    end
  end
end
