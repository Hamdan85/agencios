# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # OAuth Step 2 — exchange the authorization `code` for a short-lived user
      # token. GET /oauth/access_token (instagram.md/facebook.md §4).
      class ExchangeCodeForToken
        def self.call(...) = new(...).call

        # redirect_uri MUST match the one used in the authorize dialog.
        def initialize(code:, redirect_uri:, client: nil)
          @code = code
          @redirect_uri = redirect_uri
          @client = client || Vendors::Meta::Client.new
        end

        # Returns { "access_token" => short_lived, "token_type" =>, "expires_in" => }.
        def call
          @client.get(
            "/oauth/access_token",
            params: {
              client_id: @client.app_id,
              client_secret: @client.app_secret,
              redirect_uri: @redirect_uri,
              code: @code
            },
            token: nil
          )
        end
      end
    end
  end
end
