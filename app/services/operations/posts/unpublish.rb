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
          raise Operations::Errors::Invalid, I18n.t('operations.posts.unpublish_only_live')
        end

        manual_removal_note = delete_from_network
        @post.update!(status: :unpublished, unpublished_at: Time.current, failure_reason: manual_removal_note)

        Broadcaster.ticket(@post.ticket, 'post_unpublished', post_id: @post.id)
        key, params = note_key(manual_removal_note)
        Operations::Notes::Create.call(
          ticket: @post.ticket, user: @user, kind: :system, i18n_key: key, i18n_params: params
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
        raise Operations::Errors::Invalid,
              I18n.t('operations.posts.unpublish_failed', provider: @post.social_account.provider, message: e.message)
      end

      # Returns [i18n_key, params] for the history note (rendered per reader).
      def note_key(manual_removal_note)
        provider = @post.social_account.provider
        if manual_removal_note
          ['notes.post_unpublished_manual', { provider: provider, note: manual_removal_note }]
        else
          ['notes.post_unpublished', { provider: provider }]
        end
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
