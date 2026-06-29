# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # Uniform seam entrypoint: fetch analytics for a published post.
      #
      # IMPORTANT: the X Free tier is WRITE-ONLY — reading metrics requires a
      # read-capable tier. When metrics are unavailable (no read access / gated
      # tier), return zeros + a `raw` note rather than crashing the sync job.
      #
      # Returns { reach:, views:, likes:, comments:, shares:, saves:, raw: }.
      # See docs/integrations/x-twitter.md §7.
      class SyncInsights
        def self.call(...) = new(...).call

        def initialize(post)
          @post = post
          @social_account = post.social_account
        end

        def call
          tweet_id = @post.external_post_id.presence
          return unavailable("missing_tweet_id") if tweet_id.blank?

          data = Vendors::X::Actions::FetchMetrics.call(
            social_account: @social_account, tweet_id: tweet_id
          )
          metrics = data["public_metrics"] || {}
          map_metrics(metrics, raw: data)
        rescue Vendors::Base::AuthenticationError => e
          # Free tier (write-only) / insufficient read access.
          unavailable("read_not_available_on_tier", detail: e.message)
        rescue Vendors::Base::RateLimitError => e
          unavailable("rate_limited", detail: e.message)
        end

        private

        def map_metrics(metrics, raw:)
          {
            reach: metrics["impression_count"].to_i,
            views: metrics["impression_count"].to_i,
            likes: metrics["like_count"].to_i,
            comments: metrics["reply_count"].to_i,
            # X "shares" = retweets + quotes.
            shares: metrics["retweet_count"].to_i + metrics["quote_count"].to_i,
            saves: metrics["bookmark_count"].to_i,
            raw: raw
          }
        end

        def unavailable(reason, detail: nil)
          {
            reach: 0, views: 0, likes: 0, comments: 0, shares: 0, saves: 0,
            raw: { "unavailable" => reason, "detail" => detail }.compact
          }
        end
      end
    end
  end
end
