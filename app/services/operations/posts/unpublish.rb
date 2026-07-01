# frozen_string_literal: true

module Operations
  module Posts
    # Removes a published Post from its network (Publishers::SocialPublisher)
    # and records the result. Networks without a delete API (Instagram, Threads,
    # TikTok) can't be removed remotely — the post is still marked unpublished
    # locally with a note so the team knows to remove it by hand.
    #
    # If this was the ticket's last remaining published post, the ticket moves
    # back to `scheduled` so it can be re-posted.
    class Unpublish < Operations::Base
      def initialize(post:, user:)
        @post = post
        @user = user
      end

      def call
        unless @post.status_published?
          raise Operations::Errors::Invalid, 'Só é possível despublicar um post que está no ar.'
        end

        manual_removal_note = delete_from_network
        @post.update!(status: :unpublished, unpublished_at: Time.current, failure_reason: manual_removal_note)

        Broadcaster.ticket(@post.ticket, 'post_unpublished', post_id: @post.id)
        Operations::Notes::Create.call(
          ticket: @post.ticket, user: @user, kind: :system, body: note_body(manual_removal_note)
        )
        revert_ticket_if_no_longer_published

        @post
      end

      private

      # Returns a manual-removal note when the network has no delete API;
      # returns nil (and lets the deletion succeed or raise) otherwise.
      def delete_from_network
        Publishers::SocialPublisher.unpublish(@post)
        nil
      rescue Vendors::Base::NotSupportedError => e
        e.message
      rescue Vendors::Base::Error => e
        raise Operations::Errors::Invalid, "Não foi possível excluir no #{@post.social_account.provider}: #{e.message}"
      end

      def note_body(manual_removal_note)
        provider = @post.social_account.provider
        return "Post despublicado em #{provider}. #{manual_removal_note}" if manual_removal_note

        "Post despublicado em #{provider}."
      end

      def revert_ticket_if_no_longer_published
        ticket = @post.ticket
        return unless ticket.status == 'published'
        return if ticket.posts.where(status: Post.statuses[:published]).exists?

        Operations::Tickets::ChangeStatus.call(ticket, 'scheduled', user: @user, force: true)
      end
    end
  end
end
