# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Uniform seam entrypoint — fetches analytics for a published Post via the
      # YouTube Analytics API filtered to the post's video id (§7.1). YouTube exposes
      # views/likes/comments/shares per video; there is no per-video reach or saves in
      # this API, so reach mirrors views and saves -> 0. Returns:
      #   { reach:, views:, likes:, comments:, shares:, saves:, raw: {...} }
      class SyncInsights
        METRICS = 'views,likes,comments,shares,estimatedMinutesWatched'
        # Lifetime window — the Analytics API has no all-time, so we span a wide range.
        LOOKBACK_DAYS = 365

        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          video_id = @post.external_post_id
          return zero_metrics if video_id.blank?

          row = aggregate_row(video_id)

          {
            reach: row['views'].to_i,
            views: row['views'].to_i,
            likes: row['likes'].to_i,
            comments: row['comments'].to_i,
            shares: row['shares'].to_i,
            saves: 0,
            raw: row
          }
        end

        private

        # No `dimensions` → a single aggregate row across the window for this video.
        def aggregate_row(video_id)
          result = Vendors::Youtube::Actions::QueryAnalytics.call(
            social_account: @social_account,
            metrics: METRICS,
            start_date: start_date,
            end_date: end_date,
            filters: "video==#{video_id}"
          )
          result[:rows_as_hashes].first || {}
        rescue Vendors::Base::Error
          {}
        end

        def start_date
          (Date.current - LOOKBACK_DAYS).iso8601
        end

        def end_date
          Date.current.iso8601
        end

        def zero_metrics
          { reach: 0, views: 0, likes: 0, comments: 0, shares: 0, saves: 0, raw: {} }
        end
      end
    end
  end
end
