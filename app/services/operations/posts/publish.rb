# frozen_string_literal: true

module Operations
  module Posts
    # Publishes one Post through the SocialPublisher seam, recording the result
    # and broadcasting. Called by PublishPostJob (enqueued when a ticket enters
    # `published`).
    class Publish < Operations::Base
      def initialize(post:)
        @post = post
      end

      def call
        guard_media_support!
        @post.update!(status: :publishing)
        Broadcaster.ticket(@post.ticket, "post_publishing", post_id: @post.id)

        result = Publishers::SocialPublisher.publish(@post)

        @post.update!(
          status: :published,
          published_at: Time.current,
          external_post_id: result[:external_post_id] || result["external_post_id"],
          permalink: result[:permalink] || result["permalink"]
        )
        Broadcaster.ticket(@post.ticket, "post_published", post_id: @post.id, permalink: @post.permalink)
        notify("Post publicado em #{@post.social_account.provider} ✅", @post.ticket.title)
        email { |to| PostMailer.published(post: @post, recipient: to) }
        advance_ticket_if_all_published
        @post
      rescue StandardError => e
        @post.update!(status: :failed, failure_reason: e.message.to_s[0, 500])
        Operations::Notes::Create.call(
          ticket: @post.ticket, user: nil, kind: :system,
          body: "Falha ao publicar em #{@post.social_account.provider}: #{e.message}"
        )
        Broadcaster.ticket(@post.ticket, "post_failed", post_id: @post.id)
        notify("Falha ao publicar em #{@post.social_account.provider}", @post.ticket.title)
        email { |to| PostMailer.failed(post: @post, recipient: to, reason: e.message) }
        raise
      end

      private

      # A network only posts media it supports (e.g. TikTok/YouTube are video-only).
      # Guard here too so a scheduled/cron-published post can never send an
      # unsupported asset.
      def guard_media_support!
        creative = @post.publishable_creative
        return if creative.nil?

        provider = @post.social_account.provider
        return if Publishers::SocialPublisher.supports?(provider, creative.media_kind)

        raise Vendors::Base::Error, "#{provider} não suporta #{creative.media_kind}."
      end

      # The ticket reaches "No ar" only once posting actually succeeds. When the
      # last pending post of a ticket in the posting step publishes, advance it.
      def advance_ticket_if_all_published
        ticket = @post.ticket
        return unless ticket.status == "scheduled"
        return if ticket.posts.where.not(status: Post.statuses[:published]).exists?

        Operations::Tickets::ChangeStatus.call(ticket, "published", user: nil, force: true)
      rescue StandardError => e
        Rails.logger.warn("[Posts::Publish] auto-advance to published failed: #{e.message}")
      end

      # Publishing runs in a background job (no acting user) — notify whoever owns
      # the ticket: the assignee, falling back to its creator.
      def notify(title, body)
        Operations::Push::Notify.call(
          user: @post.ticket.assignee || @post.ticket.created_by,
          title:, body:, path: "/tickets/#{@post.ticket_id}"
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
