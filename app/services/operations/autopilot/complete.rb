# frozen_string_literal: true

module Operations
  module Autopilot
    # Terminal step for a ticket-run: GO produces the creatives and STOPS in
    # `production` with the pieces ready. It never sends them to the client on its
    # own — a human reviews the work and clicks "Enviar para aprovação"
    # (ApprovalPanel → Approvals::RequestApproval). GO resumes by itself only after
    # the client approves (Approvals::OnFullyApproved schedules the posts).
    #
    # Also relocates the old PublishStep#finish side-effects (spent credits,
    # broadcasts, owner push, batch recompute).
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
        Operations::Autopilot::RecomputeBatch.call(batch_id: @run.batch_id) if @run.batch_id
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
