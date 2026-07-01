# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # FB page-level insights — GET /{page_id}/insights (facebook.md §7a).
      # `impressions`/page-fans metrics are being retired; prefer views/follows.
      class GetPageInsights
        def self.call(...) = new(...).call

        DEFAULT_METRICS = %w[
          page_views_total page_post_engagements page_impressions_unique
          page_fan_adds page_video_views page_actions_post_reactions_total
        ].freeze

        def initialize(social_account:, metrics: DEFAULT_METRICS, period: 'day',
                       since: nil, until_time: nil, client: nil)
          @social_account = social_account
          @metrics = metrics
          @period = period
          @since = since
          @until_time = until_time
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get(
            "/#{@social_account.page_id}/insights",
            params: {
              metric: Array(@metrics).join(','),
              period: @period,
              since: @since,
              until: @until_time
            }
          )
        end
      end
    end
  end
end
