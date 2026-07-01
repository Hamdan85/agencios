# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # GET /rest/organizationalEntityFollowerStatistics?q=organizationalEntity&organizationalEntity={urn}
      # Lifetime follower demographics (or time-bound gains if timeIntervals given).
      # Org-only; needs rw_organization_admin.
      # See docs/integrations/linkedin.md §7b.
      class FetchFollowerStatistics
        def self.call(...) = new(...).call

        def initialize(social_account:, org_urn:)
          @social_account = social_account
          @org_urn = org_urn
        end

        # Returns the parsed body ({ "elements" => [...] }).
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          client.rest_get(
            '/rest/organizationalEntityFollowerStatistics',
            q: 'organizationalEntity', organizationalEntity: @org_urn
          )
        end
      end
    end
  end
end
