# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # IG account/user insights — GET /{ig_user_id}/insights with
      # metric_type=total_value (instagram.md §7a). Most aggregate metrics now
      # require metric_type=total_value; `impressions` is deprecated → `views`.
      class GetAccountInsights
        def self.call(...) = new(...).call

        DEFAULT_METRICS = %w[
          reach views profile_views accounts_engaged total_interactions
          likes comments saves shares replies
        ].freeze

        def initialize(social_account:, metrics: DEFAULT_METRICS, period: "day",
                       since: nil, until_time: nil, metric_type: "total_value", client: nil)
          @social_account = social_account
          @metrics = metrics
          @period = period
          @since = since
          @until_time = until_time
          @metric_type = metric_type
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          @client.get(
            "/#{@social_account.ig_user_id}/insights",
            params: {
              metric: Array(@metrics).join(","),
              metric_type: @metric_type,
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
