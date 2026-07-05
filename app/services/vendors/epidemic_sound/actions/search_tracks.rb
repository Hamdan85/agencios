# frozen_string_literal: true

module Vendors
  module EpidemicSound
    module Actions
      # Search the licensed catalog and return the BEST burnable track for the
      # query (or nil when Epidemic Sound isn't configured / nothing matched / it
      # errors). Never raises to the caller — a missing soundtrack must never fail
      # a video (ResolveMusic then falls back to the admin catalog).
      class SearchTracks
        def self.call(...) = new(...).call

        def initialize(query:, tags: nil, instrumental: true)
          @query = query
          @tags = tags
          @instrumental = instrumental
        end

        def call
          client = Vendors::EpidemicSound::Client.new
          return nil unless client.configured?

          client.search(query: @query, tags: @tags, limit: 5, instrumental: @instrumental).first
        rescue StandardError => e
          Rails.logger.warn("[EpidemicSound::SearchTracks] #{e.class}: #{e.message}")
          nil
        end
      end
    end
  end
end
