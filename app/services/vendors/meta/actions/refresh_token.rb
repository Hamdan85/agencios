# frozen_string_literal: true

module Vendors
  module Meta
    module Actions
      # Uniform seam entrypoint — renew the long-lived USER token before it
      # expires (~day 60) by re-exchanging the current long-lived token via
      # fb_exchange_token (instagram.md §4 / facebook.md §4). Meta has no separate
      # refresh token; the renewal IS the long-lived exchange. Page tokens derived
      # from a current user token stay valid, so we only refresh the user token.
      #
      # Returns updated token attrs to persist on the SocialAccount.
      class RefreshToken
        def self.call(...) = new(...).call

        def initialize(social_account, client: nil)
          @social_account = social_account
          @client = client || Vendors::Meta::Client.new(social_account)
        end

        def call
          result = ExchangeLongLivedToken.call(
            short_lived_token: @social_account.user_access_token,
            client: @client
          )

          {
            user_access_token: result["access_token"],
            refresh_token: nil,
            token_expires_at: expiry_from(result["expires_in"])
          }
        end

        private

        def expiry_from(expires_in)
          seconds = expires_in.to_i
          return nil if seconds.zero?

          Time.current + seconds.seconds
        end
      end
    end
  end
end
