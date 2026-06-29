# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Step 2 — exchange the authorization code for tokens.
      # POST https://www.linkedin.com/oauth/v2/accessToken (grant_type=authorization_code)
      # See docs/integrations/linkedin.md §4.
      class ExchangeCode
        def self.call(...) = new(...).call

        def initialize(code:, redirect_uri:)
          @code = code
          @redirect_uri = redirect_uri
        end

        # Returns the raw token body:
        #   { access_token:, expires_in:, refresh_token?:, refresh_token_expires_in?:, scope: }
        def call
          client = Vendors::Linkedin::Client.new
          client.token_request(
            grant_type: "authorization_code",
            code: @code,
            client_id: client.client_id,
            client_secret: client.client_secret,
            redirect_uri: @redirect_uri
          )
        end
      end
    end
  end
end
