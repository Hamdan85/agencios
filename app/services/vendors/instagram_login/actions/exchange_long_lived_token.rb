# frozen_string_literal: true

module Vendors
  module InstagramLogin
    module Actions
      # OAuth step 3 — short-lived → long-lived (~60 day) Instagram user token
      # (instagram-login.md §4). GET graph.instagram.com/access_token.
      # Returns { "access_token" => ..., "token_type" => "bearer", "expires_in" => 5183944 }.
      class ExchangeLongLivedToken
        def self.call(...) = new(...).call

        def initialize(short_lived_token:, client: nil)
          @short_lived_token = short_lived_token
          @client = client || Vendors::InstagramLogin::Client.new
        end

        def call
          @client.graph_get(
            "/access_token",
            params: {
              grant_type: "ig_exchange_token",
              client_secret: @client.app_secret,
              access_token: @short_lived_token
            },
            token: nil
          )
        end
      end
    end
  end
end
