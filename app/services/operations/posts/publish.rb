# frozen_string_literal: true

module Operations
  module Posts
    # Publishes one Post through the SocialPublisher seam, recording the result
    # and broadcasting. Called by PublishPostJob (enqueued when a ticket enters
    # `published`).
    #
    # This owns ONLY the happy path. On error it simply re-raises: the job decides
    # whether the error is transient (retry silently, keeping the post in
    # `publishing`) or terminal (hand off to Operations::Posts::MarkPublishFailed).
    # This is what stops a mid-retry attempt from prematurely marking the post
    # failed and spamming an alert + failure email while it is still going to
    # succeed on a later attempt.
    #
    # A direct-vendor account finishes synchronously — the vendor call above
    # already blocked until the post was live — so the result is handed straight
    # to Operations::Posts::MarkPublished. A postgate-sourced account may instead
    # come back `pending: true` (PostGate is still processing the target
    # server-side): the post STAYS `publishing`, no notification fires yet, and
    # Posts::PollPostgateStatusJob takes over until PostGate (poll or webhook)
    # settles it.
    class Publish < Operations::Base
      def initialize(post:)
        @post = post
      end

      def call
        guard_client_active!
        guard_media_support!
        @post.update!(status: :publishing)
        Broadcaster.ticket(@post.ticket, 'post_publishing', post_id: @post.id)

        result = Publishers::SocialPublisher.publish(@post)

        persist_postgate_id(result)
        return handle_pending if pending?(result)

        Operations::Posts::MarkPublished.call(
          post: @post,
          external_post_id: result[:external_post_id] || result['external_post_id'],
          permalink: result[:permalink] || result['permalink']
        )
      end

      private

      def pending?(result)
        !!(result[:pending] || result['pending'])
      end

      # The PostGate post id must survive on BOTH outcomes — the pending hand-off
      # AND an immediate success — because metric syncs (post_stats) and unpublish
      # (delete_post) address the post by it later.
      def persist_postgate_id(result)
        postgate_post_id = result[:postgate_post_id] || result['postgate_post_id']
        @post.update!(postgate_post_id: postgate_post_id) if postgate_post_id.present?
      end

      # PostGate accepted the post but hasn't confirmed the target published yet.
      # Leave the post `publishing` and hand off to the poll job instead of
      # notifying/broadcasting a success we don't have yet.
      def handle_pending
        ::Posts::PollPostgateStatusJob.set(wait: 10.seconds).perform_later(@post.id, 1)
        @post
      end

      # An archived client is frozen — nothing new goes live under its name. The
      # cron sweep already skips these, so this only bites a manual/MCP publish of
      # a post whose campaign/client was archived after scheduling; it gets a clear
      # 422 instead of quietly going out.
      def guard_client_active!
        return unless @post.ticket&.project&.status_archived?

        raise Operations::Errors::Invalid,
              I18n.t('operations.posts.project_archived')
      end

      # A network only posts media it supports (e.g. TikTok/YouTube are video-only).
      # Guard here too so a scheduled/cron-published post can never send an
      # unsupported asset.
      def guard_media_support!
        creative = @post.publishable_creative
        return if creative.nil?

        provider = @post.social_account.provider
        return if Publishers::SocialPublisher.supports?(provider, creative.media_kind)

        raise Vendors::Base::Error, I18n.t('operations.posts.unsupported_media', provider: provider, media: creative.media_kind)
      end
    end
  end
end
