# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # OAuth step 3 — short-lived → long-lived (~60 day) Threads user token
      # (threads.md §4). GET graph.threads.net/access_token.
      # Returns { "access_token" => ..., "token_type" => "bearer", "expires_in" => ... }.
      class ExchangeLongLivedToken
        def self.call(...) = new(...).call

        def initialize(short_lived_token:, client: nil)
          @short_lived_token = short_lived_token
          @client = client || Vendors::Threads::Client.new
        end

        def call
          @client.oauth_get(
            "/access_token",
            params: {
              grant_type: "th_exchange_token",
              client_secret: @client.app_secret,
              access_token: @short_lived_token
            }
          )
        end
      end
    end
  end
end
