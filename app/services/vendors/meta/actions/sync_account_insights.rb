# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint for PROFILE-level analytics (the account vanity
      # numbers a report opens with), normalized to:
      #   { followers:, new_followers:, accounts_reached:, profile_views:,
      #     views:, story_replies:, total_interactions:, raw: }
      #
      # Instagram only (the deck is an IG audit); Facebook Pages could be added via
      # GetPageInsights. Each sub-call is independently guarded so one unsupported
      # metric never zeroes the whole snapshot. (instagram.md §7a.)
      class SyncAccountInsights
        def self.call(...) = new(...).call

        # Aggregate, point-in-time metrics (metric_type=total_value).
        TOTAL_METRICS = %w[reach profile_views views total_interactions replies].freeze
        # Time-series metric: daily new follows, summed across the window.
        TIMESERIES_METRICS = %w[follower_count].freeze

        def initialize(social_account, since: nil, until_time: nil, client: nil)
          @social_account = social_account
          @since = since
          @until_time = until_time
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          return empty unless @social_account.provider_instagram?

          fields = account_fields
          totals = total_value_insights
          series = timeseries_insights

          {
            followers: int(fields["followers_count"]),
            new_followers: series.fetch(:follower_count, 0),
            accounts_reached: int(totals["reach"]),
            profile_views: int(totals["profile_views"]),
            views: int(totals["views"]),
            story_replies: int(totals["replies"]),
            total_interactions: int(totals["total_interactions"]),
            raw: { fields: fields, totals: totals, series: series }
          }
        end

        private

        def account_fields
          GetAccountFields.call(social_account: @social_account, client: @client)
        rescue Vendors::Base::Error
          {}
        end

        def total_value_insights
          body = GetAccountInsights.call(
            social_account: @social_account, client: @client,
            metrics: TOTAL_METRICS, metric_type: "total_value",
            since: epoch(@since), until_time: epoch(@until_time)
          )
          index_total_value(body)
        rescue Vendors::Base::Error
          {}
        end

        # follower_count is a daily time series; sum every datapoint in the window.
        def timeseries_insights
          body = GetAccountInsights.call(
            social_account: @social_account, client: @client,
            metrics: TIMESERIES_METRICS, metric_type: "time_series", period: "day",
            since: epoch(@since), until_time: epoch(@until_time)
          )
          Array(body["data"]).each_with_object({}) do |metric, acc|
            name = metric["name"].to_s
            acc[name.to_sym] = Array(metric["values"]).sum { |v| int(v["value"]) }
          end
        rescue Vendors::Base::Error
          {}
        end

        # total_value insights → { name => value }.
        def index_total_value(body)
          Array(body["data"]).each_with_object({}) do |metric, acc|
            acc[metric["name"]] = metric.dig("total_value", "value")
          end
        end

        def epoch(time)
          return nil if time.blank?

          time.respond_to?(:to_i) ? time.to_i : time
        end

        def empty
          {
            followers: 0, new_followers: 0, accounts_reached: 0, profile_views: 0,
            views: 0, story_replies: 0, total_interactions: 0, raw: {}
          }
        end

        def int(value) = value.to_i
      end
    end
  end
end
