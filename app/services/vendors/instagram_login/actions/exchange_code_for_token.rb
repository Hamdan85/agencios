# frozen_string_literal: true

module Vendors
  module InstagramLogin
    module Actions
      # OAuth step 2 — exchange the authorization code for a SHORT-LIVED Instagram
      # user token (instagram-login.md §4). POST form to api.instagram.com.
      # Returns { "access_token" => ..., "user_id" => ..., "permissions" => [...] }.
      class ExchangeCodeForToken
        def self.call(...) = new(...).call

        def initialize(code:, redirect_uri:, client: nil)
          @code = code
          @redirect_uri = redirect_uri
          @client = client || Vendors::InstagramLogin::Client.new
        end

        def call
          @client.oauth_post(
            '/oauth/access_token',
            params: {
              client_id: @client.app_id,
              client_secret: @client.app_secret,
              grant_type: 'authorization_code',
              redirect_uri: @redirect_uri,
              code: @code
            }
          )
        end
      end
    end
  end
end
