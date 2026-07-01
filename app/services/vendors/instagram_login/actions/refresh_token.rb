# frozen_string_literal: true

module Vendors
  module InstagramLogin
    module Actions
      # Uniform seam entrypoint — renew the long-lived IG user token before it
      # expires (~day 50 of 60), extending it ~60 more days
      # (instagram-login.md §4). GET graph.instagram.com/refresh_access_token.
      #
      # Returns updated token attrs to persist on the SocialAccount (same shape as
      # Vendors::Meta::Actions::RefreshToken so Operations::Social::RefreshToken
      # treats both uniformly).
      class RefreshToken
        def self.call(...) = new(...).call

        def initialize(social_account, client: nil)
          @social_account = social_account
          @client = client || Vendors::InstagramLogin::Client.new(social_account)
        end

        def call
          result = @client.graph_get(
            '/refresh_access_token',
            params: { grant_type: 'ig_refresh_token', access_token: @social_account.user_access_token },
            token: nil
          )

          {
            user_access_token: result['access_token'],
            token_expires_at: expiry_from(result['expires_in'])
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
