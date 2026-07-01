# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Builds the 3-legged OAuth authorize URL (Step 1).
      # GET https://www.linkedin.com/oauth/v2/authorization
      # See docs/integrations/linkedin.md §4.
      class AuthorizeUrl
        def self.call(...) = new(...).call

        # Member posting + member identity are self-serve; org scopes need
        # Community Management approval. We request the full production set so a
        # single grant covers identity + member posting + org posting + org stats.
        SCOPES = %w[
          openid profile email
          w_member_social r_member_social
          r_organization_social w_organization_social rw_organization_admin
        ].freeze

        def initialize(workspace:, redirect_uri:, state:, scopes: SCOPES)
          @workspace = workspace
          @redirect_uri = redirect_uri
          @state = state
          @scopes = scopes
        end

        def call
          client = Vendors::Linkedin::Client.new
          query = URI.encode_www_form(
            response_type: 'code',
            client_id: client.client_id,
            redirect_uri: @redirect_uri,
            state: @state,
            scope: @scopes.join(' ')
          )
          "#{Vendors::Linkedin::Client::OAUTH_HOST}/oauth/v2/authorization?#{query}"
        end
      end
    end
  end
end
