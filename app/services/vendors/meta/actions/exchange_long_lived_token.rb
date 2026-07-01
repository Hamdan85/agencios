# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # OAuth Step 3 — exchange a short-lived user token for a long-lived (~60d)
      # user token. Also used to RENEW a long-lived token before expiry by
      # passing the current long-lived token (instagram.md/facebook.md §4).
      class ExchangeLongLivedToken
        def self.call(...) = new(...).call

        def initialize(short_lived_token:, client: nil)
          @short_lived_token = short_lived_token
          @client = client || Vendors::Meta::Client.new
        end

        # Returns { "access_token" => long_lived, "token_type" =>, "expires_in" => }.
        def call
          @client.get(
            '/oauth/access_token',
            params: {
              grant_type: 'fb_exchange_token',
              client_id: @client.app_id,
              client_secret: @client.app_secret,
              fb_exchange_token: @short_lived_token
            },
            token: nil
          )
        end
      end
    end
  end
end
