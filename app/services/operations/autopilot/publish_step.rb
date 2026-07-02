# frozen_string_literal: true

module Operations
  module Autopilot
    # Phase 3: schedule the posts. Moves the ticket into `scheduled` and reuses the
    # authoritative Operations::Tickets::Publish (which now bundles video + cover +
    # story into one post per network). With `mode: scheduled` the posts land in
    # the `scheduled` state for MonitorScheduledPostsJob to publish at the strategy
    # date — the run is "generate + schedule", so it completes here even though the
    # actual publish happens later (the user can still edit the schedule).
    class PublishStep < Operations::Base
      def initialize(run:)
        @run = run
        @ticket = run.ticket
      end

      def call
        return unless claim!

        move_to_scheduled
        result = Operations::Tickets::Publish.call(
          ticket: @ticket, user: @run.user,
          creative_ids: ready_creative_ids,
          mode: @run.mode, scheduled_at: @run.scheduled_at
        )
        finish(result)
      end

      private

      def claim!
        @run.with_lock do
          next false unless @run.state == 'publishing'

          @run.update!(progress: @run.progress.merge('publishing_claimed' => true))
          true
        end
      end

      def move_to_scheduled
        return unless @ticket.production?

        Operations::Tickets::ChangeStatus.call(@ticket, 'scheduled', user: @run.user, force: true)
        @ticket.reload
      end

      # Only the ready creatives autopilot produced (a failed video would have
      # halted the run before here, but stay defensive).
      def ready_creative_ids
        @ticket.creatives.where(id: @run.creative_ids).status_ready.pluck(:id).map(&:to_s)
      end

      def finish(result)
        @run.update!(
          state: 'completed', finished_at: Time.current, spent_credits: computed_spent,
          progress: @run.progress.merge(
            'posts' => Array(result[:posts]), 'skipped' => Array(result[:skipped])
          )
        )
        Broadcaster.ticket(@ticket, 'autopilot_completed', run_id: @run.id, posts: Array(result[:posts]).size)
        Broadcaster.board(@run.workspace_id, 'autopilot_completed', ticket_id: @ticket.id, run_id: @run.id)
        notify_owner
        Operations::Autopilot::RecomputeBatch.call(batch_id: @run.batch_id) if @run.batch_id
        @run
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
          body: "#{@ticket.display_title}: criativos gerados e posts agendados.",
          path: "/tickets/#{@ticket.id}"
        )
      rescue StandardError => e
        Rails.logger.warn("[Autopilot::PublishStep] notify failed: #{e.message}")
      end
    end
  end
end
