# frozen_string_literal: true

module Operations
  module Approvals
    # The hands-off branch (auto_publish_after_approval ON): with the ticket already
    # in the Publication phase and its scheduled_at pre-filled by OnFullyApproved,
    # reuse Tickets::Publish to create the scheduled posts. They remain reviewable /
    # editable / cancelable in the Publication phase until they fire. This is the
    # only publish path — no new one. (Replaces the earlier ScheduleApproved.)
    class AutoPublishApproved < Operations::Base
      def initialize(ticket:, user: nil)
        @ticket = ticket
        @user = user
      end

      def call
        return unless @ticket.scheduled?

        Operations::Tickets::Publish.call(
          ticket: @ticket, user: @user,
          creative_ids: @ticket.approvable_creatives.map { |c| c.id.to_s },
          mode: 'scheduled', scheduled_at: @ticket.scheduled_at
        )
        @ticket
      end
    end
  end
end
