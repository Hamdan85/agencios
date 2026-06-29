# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Per-post share statistics (lifetime only). Wraps FetchShareStatistics with
      # a specific share URN list. Posts with zero activity are omitted — treat as
      # all-zero.
      # See docs/integrations/linkedin.md §7a.
      class FetchPostStatistics
        def self.call(...) = new(...).call

        def initialize(social_account:, org_urn:, share_urn:)
          @social_account = social_account
          @org_urn = org_urn
          @share_urn = share_urn
        end

        # Returns the totalShareStatistics hash for the post (or {} if omitted).
        def call
          body = Vendors::Linkedin::Actions::FetchShareStatistics.call(
            social_account: @social_account,
            org_urn: @org_urn,
            shares: [@share_urn]
          )
          element = Array(body["elements"]).first
          element&.dig("totalShareStatistics") || {}
        end
      end
    end
  end
end
