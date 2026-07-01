# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB per-post insights — GET /{post_id}/insights (facebook.md §7b).
      #
      # Scope: reach/views ONLY. Likes/comments/shares come from the stable post
      # object (GetPostEngagement), NOT from insights — Meta deprecates insights
      # metrics aggressively (post_impressions* and the unique-reach family were
      # retired across all versions by 2025-11 / 2026-06). The call is resilient:
      # any metric the API rejects is dropped and the rest still return.
      class GetPostInsights
        def self.call(...) = new(...).call

        # Reach/views candidates, newest-first. Whatever the current Graph version
        # still accepts survives insights_get's drop-and-retry; the rest fall away.
        DEFAULT_METRICS = %w[
          post_impressions_unique post_impressions post_video_views
        ].freeze

        def initialize(social_account:, post_id:, metrics: DEFAULT_METRICS, client: nil)
          @social_account = social_account
          @post_id = post_id
          @metrics = metrics
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.insights_get("/#{@post_id}/insights", metrics: @metrics)
        end
      end
    end
  end
end
