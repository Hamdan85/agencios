# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # GET /2/tweets/:id?tweet.fields=public_metrics (single) or
      # GET /2/tweets?ids=...&tweet.fields=public_metrics (batch).
      # Needs a READ-capable tier — the Free tier is write-only and returns no
      # metrics (see the caller for graceful zero handling).
      # See docs/integrations/x-twitter.md §7.
      class FetchMetrics
        def self.call(...) = new(...).call

        def initialize(social_account:, tweet_id: nil, tweet_ids: nil, fields: "public_metrics")
          @social_account = social_account
          @tweet_id = tweet_id
          @tweet_ids = Array(tweet_ids).compact
          @fields = fields
        end

        # Single: returns the tweet's public_metrics hash (+ "id").
        # Batch: returns an array of { "id", "public_metrics" } hashes.
        def call
          client = Vendors::X::Client.new(social_account: @social_account)

          if @tweet_ids.any?
            body = client.get_json("/2/tweets", ids: @tweet_ids.join(","), "tweet.fields": @fields)
            Array(body["data"])
          else
            body = client.get_json("/2/tweets/#{@tweet_id}", "tweet.fields": @fields)
            body["data"] || {}
          end
        end
      end
    end
  end
end
