# frozen_string_literal: true

module Operations
  module Autopilot
    # Terminal step for a ticket-run under the new lifecycle: GO stops at
    # `production` with creatives ready. Relocates the old PublishStep#finish
    # side-effects (spent credits, broadcasts, owner push, batch recompute) and
    # requests client approval when the project requires it.
    class Complete < Operations::Base
      def initialize(run:)
        @run = run
        @ticket = run.ticket
      end

      def call
        return unless claim!

        @run.update!(
          state: 'completed', finished_at: Time.current, spent_credits: computed_spent
        )
        Broadcaster.ticket(@ticket, 'autopilot_completed', run_id: @run.id, posts: 0)
        Broadcaster.board(@run.workspace_id, 'autopilot_completed', ticket_id: @ticket.id, run_id: @run.id)
        notify_owner
        # Batch coordination first: a (rare) approval-request failure below raises
        # loudly instead of being swallowed, and must not strand the batch — on a
        # job retry `claim!` no-ops, so anything after a raise never re-runs.
        Operations::Autopilot::RecomputeBatch.call(batch_id: @run.batch_id) if @run.batch_id
        request_approval_if_needed
        @run
      end

      private

      # Claim out of the last active phase exactly once (both the sync and async
      # generation paths call Complete).
      def claim!
        @run.with_lock do
          next false if @run.terminal? || @run.progress['completed_claimed']

          @run.update!(progress: @run.progress.merge('completed_claimed' => true))
          true
        end
      end

      def request_approval_if_needed
        return unless @ticket.project.setting('require_client_approval')
        # Nothing to approve yet — e.g. a video-only ticket that GO didn't generate
        # (video waits for manual production). Don't drop an empty item in the portal.
        return unless @ticket.approvable_creatives.any?

        Operations::Approvals::RequestApproval.call(ticket: @ticket, sent_by: @run.user)
      end

      def computed_spent
        @run.workspace.credit_transactions.debits
            .where(generation_id: @run.generation_ids).sum(:amount).abs
      end

      def notify_owner
        return if @run.user.nil?

        Operations::Push::Notify.call(
          user: @run.user,
          title: 'Campanha no piloto automático ✅',
          body: "#{@ticket.display_title}: criativos gerados e prontos para aprovação.",
          path: "/tickets/#{@ticket.id}"
        )
      rescue StandardError => e
        Rails.logger.warn("[Autopilot::Complete] notify failed: #{e.message}")
      end
    end
  end
end
