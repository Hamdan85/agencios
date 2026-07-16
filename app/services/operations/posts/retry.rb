# frozen_string_literal: true

module Operations
  module Posts
    # Retries ONE failed publication on its own network. Re-arms the post (back
    # to `scheduled`, failure cleared, moment = now) and enqueues its publish
    # job — the same path an immediate publish takes, touching no other post of
    # the ticket (so a sibling that already went live is never duplicated).
    #
    # Only `failed` posts qualify: a scheduled one is already on its way, and a
    # live post has nothing to retry.
    class Retry < Operations::Base
      def initialize(post:)
        @post = post
      end

      def call
        unless @post.status_failed?
          raise Operations::Errors::Invalid,
                I18n.t('operations.posts.retry_only_failed')
        end

        @post.update!(status: :scheduled, failure_reason: nil, scheduled_at: Time.current)
        PublishPostJob.perform_later(@post.id)
        Broadcaster.ticket(@post.ticket, 'ticket_updated', status: @post.ticket.status)
        @post
      end
    end
  end
end
