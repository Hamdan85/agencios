# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # GET /rest/organizationAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED
      # Lists the Pages the authenticated member administers. Each element carries
      # organizationTarget: "urn:li:organization:{id}".
      # Requires rw_organization_admin / r_organization_admin (partner-approved).
      # See docs/integrations/linkedin.md §5.
      class FetchAdminOrganizations
        def self.call(...) = new(...).call

        def initialize(access_token: nil, social_account: nil)
          @access_token = access_token
          @social_account = social_account
        end

        # Returns an array of org URNs: ["urn:li:organization:5515715", ...].
        def call
          client = Vendors::Linkedin::Client.new(
            access_token: @access_token, social_account: @social_account
          )
          body = client.rest_get(
            '/rest/organizationAcls',
            q: 'roleAssignee', role: 'ADMINISTRATOR', state: 'APPROVED'
          )
          Array(body['elements']).map { |el| el['organizationTarget'] }.compact
        rescue Vendors::Base::AuthenticationError
          # Org scopes are partner-gated; absent approval this 401/403s. Member
          # posting still works, so degrade gracefully to "no admin orgs".
          []
        end
      end
    end
  end
end
