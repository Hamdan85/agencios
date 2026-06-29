# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # GET /rest/organizationalEntityShareStatistics?q=organizationalEntity&organizationalEntity={urn}
      # Lifetime aggregate org share statistics. Org-only; needs rw_organization_admin.
      # Optionally per-post via `shares` (urn:li:share:...) list.
      # See docs/integrations/linkedin.md §7a.
      class FetchShareStatistics
        def self.call(...) = new(...).call

        def initialize(social_account:, org_urn:, shares: nil)
          @social_account = social_account
          @org_urn = org_urn
          @shares = Array(shares).presence
        end

        # Returns the parsed body ({ "elements" => [{ "totalShareStatistics" => {...} }] }).
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          params = {
            q: "organizationalEntity",
            organizationalEntity: @org_urn
          }
          # Per-post stats: shares=List(urn%3Ali%3Ashare%3A...). The Rest.li client
          # URL-encodes the value; we pass the List(...) wrapper literally.
          params[:shares] = "List(#{@shares.join(',')})" if @shares
          client.rest_get("/rest/organizationalEntityShareStatistics", params)
        end
      end
    end
  end
end
