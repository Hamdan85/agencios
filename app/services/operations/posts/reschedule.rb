# frozen_string_literal: true

module Operations
  module Posts
    # Moves every still-scheduled post of a ticket to a new posting time.
    #
    # Publishing is sweep-based (MonitorScheduledPostsJob publishes posts whose
    # `scheduled_at` has passed), so the POST row is the source of truth for when
    # content actually goes live. Whenever the ticket's posting time changes
    # (posting step field, drawer meta, calendar drag), callers must run this —
    # otherwise the edit only touches the ticket and the old time still publishes.
    #
    # Only `scheduled` posts move; anything already publishing/published/failed
    # keeps its history. A blank time is a no-op (a scheduled post must have one).
    class Reschedule < Operations::Base
      def initialize(ticket:, scheduled_at:)
        @ticket = ticket
        @scheduled_at = scheduled_at
      end

      def call
        return [] if @scheduled_at.blank?

        posts = @ticket.posts.status_scheduled.where.not(scheduled_at: @scheduled_at).to_a
        posts.each { |post| post.update!(scheduled_at: @scheduled_at) }
        posts
      end
    end
  end
end
