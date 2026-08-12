# frozen_string_literal: true

module Operations
  module Posts
    # The terminal SUCCESS path for a Post publish — update to `published` +
    # broadcast + notify the owner + email + clear any resolved alert + advance
    # the ticket once every post is live. Extracted out of Operations::Posts::
    # Publish so it can be shared by:
    #   - the direct-vendor path (Publish calls it straight after a synchronous
    #     vendor result — SocialPublisher already blocked until the post was live);
    #   - the PostGate async path (Posts::PollPostgateStatusJob, and the PostGate
    #     webhook handler) once PostGate itself confirms the target published.
    #
    # nil-safe: passing external_post_id/permalink as nil keeps whatever value the
    # post already carries (a direct-vendor publish always has both up front; a
    # PostGate publish may only learn them once polling/webhook resolves it).
    #
    # Idempotent: a later call on an already-published post (e.g. a poll losing
    # the race to a webhook, or vice versa) is a no-op — we never re-notify or
    # re-broadcast a post that already went out.
    class MarkPublished < Operations::Base
      def initialize(post:, external_post_id: nil, permalink: nil)
        @post = post
        @external_post_id = external_post_id
        @permalink = permalink
      end

      def call
        return @post if @post.status_published?

        @post.update!(
          status: :published,
          published_at: Time.current,
          failure_reason: nil,
          external_post_id: @external_post_id || @post.external_post_id,
          permalink: @permalink || @post.permalink
        )
        Broadcaster.ticket(@post.ticket, 'post_published', post_id: @post.id, permalink: @post.permalink)
        notify('push.post.published.title', { provider: @post.social_account.provider }, @post.ticket.title)
        email { |to| PostMailer.published(post: @post, recipient: to) }
        clear_alert_if_resolved
        advance_ticket_if_all_published
        @post
      end

      private

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
        Rails.logger.warn("[Posts::MarkPublished] auto-advance to published failed: #{e.message}")
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
        Rails.logger.warn("[Posts::MarkPublished] email delivery failed: #{e.message}")
      end
    end
  end
end
