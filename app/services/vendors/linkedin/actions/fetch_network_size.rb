# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # GET /rest/organizations/{id}?...networkSizes... — total follower count.
      # (Total follower count is no longer in the follower-statistics endpoint.)
      # See docs/integrations/linkedin.md §7b / API reference table.
      class FetchNetworkSize
        def self.call(...) = new(...).call

        def initialize(social_account:, org_urn:)
          @social_account = social_account
          @org_urn = org_urn
        end

        # Returns the network-size body for the org's edge (firstDegreeSize).
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          encoded = Vendors::Linkedin::Client.encode_urn(@org_urn)
          client.rest_get(
            "/rest/networkSizes/#{encoded}",
            edgeType: "CompanyFollowedByMember"
          )
        end
      end
    end
  end
end
