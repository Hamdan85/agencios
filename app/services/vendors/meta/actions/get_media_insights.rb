# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG per-media insights — GET /{media_id}/insights (instagram.md §7b).
      # `impressions`/`plays`/`video_views` are deprecated → use `views`.
      class GetMediaInsights
        def self.call(...) = new(...).call

        # Default metrics cover image/carousel + Reels survivors (instagram.md §7b).
        DEFAULT_METRICS = %w[
          reach views likes comments saves shares total_interactions
        ].freeze

        def initialize(social_account:, media_id:, metrics: DEFAULT_METRICS, client: nil)
          @social_account = social_account
          @media_id = media_id
          @metrics = metrics
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get(
            "/#{@media_id}/insights",
            params: { metric: Array(@metrics).join(',') }
          )
        end
      end
    end
  end
end
