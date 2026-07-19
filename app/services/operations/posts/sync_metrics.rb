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

        m = Publishers::SocialPublisher.sync(@post)
        # Nothing readable (no external post yet, or every vendor call failed).
        # Skip the write: an all-zero row is not "this post scored zero", it is a
        # permanent hole in the chart that outlives the outage that caused it.
        return if m.blank?

        metric = @post.post_metrics.create!(
          captured_at: Time.current,
          reach: m[:reach].to_i,
          views: m[:views].to_i,
          likes: m[:likes].to_i,
          comments: m[:comments].to_i,
          shares: m[:shares].to_i,
          saves: m[:saves].to_i,
          raw: m[:raw] || {}
        )
        @post.social_account.update_column(:last_synced_at, Time.current)
        Broadcaster.ticket(@post.ticket, 'metric_updated', post_id: @post.id)
        # Also nudge the client central (login-less portal) so campaign metrics
        # refresh in real time for the client watching.
        Broadcaster.portal(@post.ticket&.project&.client, 'metric_updated',
                           post_id: @post.id, project_id: @post.ticket&.project_id)
        metric
      rescue Vendors::Base::AuthenticationError => e
        # The token is finished — an ACCOUNT problem, not a post problem. Flag it
        # so the user is asked to reconnect, then re-raise: the caller (the cron
        # sweep) logs it per post and moves on to the next one.
        Operations::Social::FlagNeedsReauth.call(social_account: @post.social_account, reason: e.message)
        raise
      end
    end
  end
end
