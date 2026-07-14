# frozen_string_literal: true

module Operations
  module Autopilot
    # Terminal step for a ticket-run under the new lifecycle: GO produces the
    # creatives and hands the ticket to the approver — it stops in `approval` with
    # the pieces ready (or in `production` when it generated nothing to approve,
    # e.g. a video-only ticket GO doesn't touch). Relocates the old
    # PublishStep#finish side-effects (spent credits, broadcasts, owner push,
    # batch recompute).
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
        send_to_approval
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

      # Hand the finished work to the approver. Entering `approval` is what sends
      # the client their link (ChangeStatus side effect); when the project gates
      # approval internally the card still stops there for the team to decide.
      def send_to_approval
        # Nothing to approve yet — e.g. a video-only ticket that GO didn't generate
        # (video waits for manual production). Leave it in Produção.
        return unless @ticket.approvable_creatives.any?
        return if @ticket.approval?

        Operations::Tickets::ChangeStatus.call(@ticket, 'approval', user: @run.user, force: true)
      end

      def computed_spent
        @run.workspace.credit_transactions.debits
            .where(generation_id: @run.generation_ids).sum(:amount).abs
      end

      def notify_owner
        return if @run.user.nil?

        Operations::Push::Notify.call(
          user: @run.user,
          title_key: 'push.autopilot.completed.title',
          body_key: 'push.autopilot.completed.body',
          params: { title: @ticket.display_title },
          path: "/tickets/#{@ticket.id}"
        )
      rescue StandardError => e
        Rails.logger.warn("[Autopilot::Complete] notify failed: #{e.message}")
      end
    end
  end
end
