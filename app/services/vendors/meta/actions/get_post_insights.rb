# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB per-post insights — GET /{post_id}/insights (facebook.md §7b).
      # `post_impressions` is being superseded by views-family metrics.
      class GetPostInsights
        def self.call(...) = new(...).call

        DEFAULT_METRICS = %w[
          post_impressions post_impressions_unique post_engaged_users post_clicks
          post_reactions_by_type_total post_video_views
        ].freeze

        def initialize(social_account:, post_id:, metrics: DEFAULT_METRICS, client: nil)
          @social_account = social_account
          @post_id = post_id
          @metrics = metrics
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get(
            "/#{@post_id}/insights",
            params: { metric: Array(@metrics).join(',') }
          )
        end
      end
    end
  end
end
