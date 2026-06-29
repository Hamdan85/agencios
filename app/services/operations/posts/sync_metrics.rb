# frozen_string_literal: true

module Operations
  module Posts
    # Pulls fresh analytics for a published Post through the SocialPublisher seam
    # and upserts a dated PostMetric. Driven by Posts::SyncMetricsJob (cron).
    class SyncMetrics < Operations::Base
      def initialize(post:)
        @post = post
      end

      def call
        return unless @post.status_published?

        m = Publishers::SocialPublisher.sync(@post) || {}
        metric = @post.post_metrics.create!(
          captured_at: Time.current,
          reach:    m[:reach].to_i,
          views:    m[:views].to_i,
          likes:    m[:likes].to_i,
          comments: m[:comments].to_i,
          shares:   m[:shares].to_i,
          saves:    m[:saves].to_i,
          raw:      m[:raw] || {}
        )
        @post.social_account.update_column(:last_synced_at, Time.current)
        Broadcaster.ticket(@post.ticket, "metric_updated", post_id: @post.id)
        metric
      end
    end
  end
end
