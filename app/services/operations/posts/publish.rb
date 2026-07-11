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

        @post.update!(
          status: :published,
          published_at: Time.current,
          failure_reason: nil,
          external_post_id: result[:external_post_id] || result['external_post_id'],
          permalink: result[:permalink] || result['permalink']
        )
        Broadcaster.ticket(@post.ticket, 'post_published', post_id: @post.id, permalink: @post.permalink)
        notify('push.post.published.title', { provider: @post.social_account.provider }, @post.ticket.title)
        email { |to| PostMailer.published(post: @post, recipient: to) }
        clear_alert_if_resolved
        advance_ticket_if_all_published
        @post
      end

      private

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

      # A clean publish with no failed posts left clears any alert the earlier
      # failure raised (the generated task stays for the record).
      def clear_alert_if_resolved
        ticket = @post.ticket
        return unless ticket.in_alert?
        return if ticket.posts.where(status: Post.statuses[:failed]).exists?

        Operations::Tickets::ClearAlert.call(ticket: ticket)
      end

      # The ticket reaches "No ar" only once posting actually succeeds. When the
      # last pending post of a ticket in the posting step publishes, advance it.
      def advance_ticket_if_all_published
        ticket = @post.ticket
        return unless ticket.status == 'scheduled'
        return if ticket.posts.where.not(status: Post.statuses[:published]).exists?

        Operations::Tickets::ChangeStatus.call(ticket, 'published', user: nil, force: true)
      rescue StandardError => e
        Rails.logger.warn("[Posts::Publish] auto-advance to published failed: #{e.message}")
      end

      # Publishing runs in a background job (no acting user) — notify whoever owns
      # the ticket: the assignee, falling back to its creator.
      def notify(title_key, params, body)
        Operations::Push::Notify.call(
          user: @post.ticket.assignee || @post.ticket.created_by,
          title_key: title_key, params: params, body: body, path: "/tickets/#{@post.ticket_id}"
        )
      end

      # Deliver a mailer to the ticket owner (assignee → creator), guarding a
      # missing recipient/address. Never let a mail failure mask the publish result.
      def email
        recipient = @post.ticket.assignee || @post.ticket.created_by
        return if recipient.nil? || recipient.email.blank?

        yield(recipient).deliver_later
      rescue StandardError => e
        Rails.logger.warn("[Posts::Publish] email delivery failed: #{e.message}")
      end
    end
  end
end
