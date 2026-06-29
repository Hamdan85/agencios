# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # Step C — exchange the authorization code (+ PKCE verifier) for tokens.
      # POST https://api.x.com/2/oauth2/token (grant_type=authorization_code)
      # Confidential client: Basic auth header (handled by the Client).
      # See docs/integrations/x-twitter.md §4.
      class ExchangeCode
        def self.call(...) = new(...).call

        def initialize(code:, redirect_uri:, code_verifier:)
          @code = code
          @redirect_uri = redirect_uri
          @code_verifier = code_verifier
        end

        # Returns the raw token body:
        #   { access_token:, refresh_token?:, expires_in:, scope:, token_type: }
        def call
          client = Vendors::X::Client.new
          client.token_request(
            grant_type: "authorization_code",
            code: @code,
            client_id: client.client_id,
            redirect_uri: @redirect_uri,
            code_verifier: @code_verifier
          )
        end
      end
    end
  end
end
