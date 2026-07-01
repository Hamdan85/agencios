# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Time-series analytics via youtubeAnalytics.reports.query (§7.1).
      # Scope: yt-analytics.readonly. The response is column-oriented (columnHeaders +
      # rows aligned by index); #rows_as_hashes zips them into per-row hashes.
      #
      #   Vendors::Youtube::Actions::QueryAnalytics.call(
      #     social_account:, metrics: "views,likes,comments,shares",
      #     start_date: "2026-01-01", end_date: "2026-06-30",
      #     dimensions: "day", filters: nil, ids: "channel==MINE"
      #   )
      #
      # Returns { headers: [...], rows: [[...]], rows_as_hashes: [{...}], raw: {...} }.
      class QueryAnalytics
        def self.call(...) = new(...).call

        def initialize(social_account:, metrics:, start_date:, end_date:,
                       dimensions: nil, filters: nil, sort: nil, ids: 'channel==MINE')
          @social_account = social_account
          @metrics = metrics
          @start_date = start_date
          @end_date = end_date
          @dimensions = dimensions
          @filters = filters
          @sort = sort
          @ids = ids
        end

        def call
          body = Vendors::Youtube::Client
                 .new(access_token: @social_account.user_access_token)
                 .reports_query(params)

          headers = Array(body['columnHeaders']).map { |h| h['name'] }
          rows = Array(body['rows'])

          {
            headers: headers,
            rows: rows,
            rows_as_hashes: rows.map { |row| headers.zip(row).to_h },
            raw: body
          }
        end

        private

        def params
          {
            ids: @ids,
            startDate: @start_date,
            endDate: @end_date,
            metrics: @metrics,
            dimensions: @dimensions,
            filters: @filters,
            sort: @sort
          }.compact
        end
      end
    end
  end
end
