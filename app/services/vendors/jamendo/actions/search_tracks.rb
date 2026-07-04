# frozen_string_literal: true

module Vendors
  module Jamendo
    module Actions
      # Search the open music base and return the BEST track for the query (or nil
      # when Jamendo isn't configured / nothing matched / it errors). Never raises
      # to the caller — a missing soundtrack must never fail a video.
      class SearchTracks
        def self.call(...) = new(...).call

        def initialize(query:, tags: nil, instrumental: true)
          @query = query
          @tags = tags
          @instrumental = instrumental
        end

        def call
          client = Vendors::Jamendo::Client.new
          return nil unless client.configured?

          client.search(query: @query, tags: @tags, limit: 5, instrumental: @instrumental).first
        rescue StandardError => e
          Rails.logger.warn("[Jamendo::SearchTracks] #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
