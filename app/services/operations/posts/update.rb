# frozen_string_literal: true

module Operations
  module Posts
    # Edits ONE not-yet-live post (caption and/or posting time) — the single
    # per-post edit authority (mirrors Cancel). Same "not live" rule: only
    # `scheduled` / `failed` posts are editable; a published post's caption and
    # time are history the network already has.
    #
    # Rescheduling a FAILED post is a retry: it returns to `scheduled` (with the
    # failure cleared) so the publish sweep picks it up at the new time.
    class Update < Operations::Base
      def initialize(post:, attributes:)
        @post = post
        @attributes = attributes.to_h.symbolize_keys.slice(:caption, :scheduled_at)
      end

      def call
        unless @post.status_scheduled? || @post.status_failed?
          raise Operations::Errors::Invalid,
                I18n.t('operations.posts.update_only_scheduled_or_failed')
        end

        attrs = @attributes.compact
        # A new time on a failed post re-arms it: back to `scheduled`, failure
        # cleared, so the sweep publishes it at the new moment.
        attrs[:status] = :scheduled if @post.status_failed? && attrs[:scheduled_at].present?
        attrs[:failure_reason] = nil if attrs[:status] == :scheduled

        @post.update!(attrs) if attrs.any?
        Broadcaster.ticket(@post.ticket, 'ticket_updated', status: @post.ticket.status)
        @post
      end
    end
  end
end
