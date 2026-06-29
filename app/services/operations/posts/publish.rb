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
        @post
      rescue StandardError => e
        @post.update!(status: :failed, failure_reason: e.message.to_s[0, 500])
        Operations::Notes::Create.call(
          ticket: @post.ticket, user: nil, kind: :system,
          body: "Falha ao publicar em #{@post.social_account.provider}: #{e.message}"
        )
        Broadcaster.ticket(@post.ticket, "post_failed", post_id: @post.id)
        notify("Falha ao publicar em #{@post.social_account.provider}", @post.ticket.title)
        raise
      end

      private

      # Publishing runs in a background job (no acting user) — notify whoever owns
      # the ticket: the assignee, falling back to its creator.
      def notify(title, body)
        Operations::Push::Notify.call(
          user: @post.ticket.assignee || @post.ticket.created_by,
          title:, body:, path: "/tickets/#{@post.ticket_id}"
        )
      end
    end
  end
end
