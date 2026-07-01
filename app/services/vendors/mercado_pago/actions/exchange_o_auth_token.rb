# frozen_string_literal: true

module Vendors
  module MercadoPago
    module Actions
      # POST /oauth/token — marketplace OAuth: exchange an authorization `code`
      # (or a `refresh_token`) for a connected-account access token, so an agency
      # receives money in its OWN Mercado Pago account.
      #
      # The connected access_token is valid 180 days; refresh before expiry with
      # grant_type "refresh_token". Persist access_token/refresh_token/user_id/
      # expiry per workspace (encrypted on Setting).
      #
      # See docs/integrations/mercado-pago.md §4.
      #
      #   # Connect (authorization_code):
      #   Vendors::MercadoPago::Actions::ExchangeOAuthToken.call(
      #     code: "TG-...", redirect_uri: "https://app/callback", code_verifier: "..."
      #   )
      #
      #   # Renew (refresh_token):
      #   Vendors::MercadoPago::Actions::ExchangeOAuthToken.call(refresh_token: "TG-...")
      #
      # Returns the parsed token body:
      #   { "access_token" =>, "refresh_token" =>, "user_id" =>, "expires_in" =>,
      #     "public_key" =>, "live_mode" =>, "scope" =>, "token_type" => }
      class ExchangeOAuthToken
        def self.call(...) = new(...).call

        def initialize(code: nil, refresh_token: nil, redirect_uri: nil,
                       code_verifier: nil, client: nil)
          @code = code
          @refresh_token = refresh_token
          @redirect_uri = redirect_uri
          @code_verifier = code_verifier
          # OAuth auth is via client_id/secret in the body — no workspace token.
          @client = client || Vendors::MercadoPago::Client.new
        end

        def call
          @client.oauth_token(body: body)
        end

        private

        def body
          base = {
            client_id: @client.client_id,
            client_secret: @client.client_secret
          }

          if @refresh_token.present?
            base[:grant_type] = 'refresh_token'
            base[:refresh_token] = @refresh_token
          else
            base[:grant_type] = 'authorization_code'
            base[:code] = @code
            base[:redirect_uri] = @redirect_uri
            base[:code_verifier] = @code_verifier if @code_verifier.present?
          end

          base
        end
      end
    end
  end
end
