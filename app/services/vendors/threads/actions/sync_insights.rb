# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # Uniform seam entrypoint — fetch insights for a published Threads post and
      # normalize to { reach:, views:, likes:, comments:, shares:, saves:, raw: }
      # (threads.md §7). Threads media metrics: views, likes, replies, reposts,
      # quotes, shares. Mapping: replies→comments, reposts+quotes+shares→shares.
      class SyncInsights
        def self.call(...) = new(...).call

        METRICS = %w[views likes replies reposts quotes shares].freeze

        def initialize(post)
          @post = post
          @account = post.social_account
        end

        # Returns nil when there is nothing to read and RAISES when the read
        # failed — persisting a failure as zeros would leave a permanent hole in
        # the chart (same contract as Meta::Actions::SyncInsights).
        def call
          return nil if @post.external_post_id.blank?

          body = Vendors::Threads::Client.new(@account).get(
            "/#{@post.external_post_id}/insights", params: { metric: METRICS.join(',') }
          )
          values = index_insights(body)

          {
            reach: int(values['views']),
            views: int(values['views']),
            likes: int(values['likes']),
            comments: int(values['replies']),
            shares: int(values['reposts']) + int(values['quotes']) + int(values['shares']),
            saves: 0,
            raw: body
          }
        end

        private

        # Threads insights come back as data:[{ name:, total_value:{ value: } }, …]
        # (or `values:[{ value: }]` for time-series). Flatten name → number.
        def index_insights(body)
          Array(body['data']).each_with_object({}) do |metric, acc|
            name = metric['name']
            value = metric.dig('total_value', 'value') || metric.dig('values', 0, 'value')
            acc[name] = value
          end
        end

        def int(value) = value.to_i

      end
    end
  end
end
