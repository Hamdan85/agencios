# frozen_string_literal: true

module Operations
  module Posts
    # Writes one dated PostMetric snapshot for a Post + broadcasts the update.
    # Extracted out of Operations::Posts::SyncMetrics (which still owns the
    # published-only guard and the blank-result skip) so the exact same write
    # path can be reused by the PostGate webhook handler, which receives metrics
    # pushed rather than pulled.
    class RecordMetric < Operations::Base
      def initialize(post:, metrics:)
        @post = post
        @m = metrics
      end

      def call
        metric = @post.post_metrics.create!(
          captured_at: Time.current,
          reach: @m[:reach].to_i,
          views: @m[:views].to_i,
          likes: @m[:likes].to_i,
          comments: @m[:comments].to_i,
          shares: @m[:shares].to_i,
          saves: @m[:saves].to_i,
          raw: @m[:raw] || {}
        )
        @post.social_account.update_column(:last_synced_at, Time.current)
        Broadcaster.ticket(@post.ticket, 'metric_updated', post_id: @post.id)
        # Also nudge the client central (login-less portal) so campaign metrics
        # refresh in real time for the client watching.
        Broadcaster.portal(@post.ticket&.project&.client, 'metric_updated',
                           post_id: @post.id, project_id: @post.ticket&.project_id)
        metric
      end
    end
  end
end
