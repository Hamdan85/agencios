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

        Operations::Posts::RecordMetric.call(post: @post, metrics: m)
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
