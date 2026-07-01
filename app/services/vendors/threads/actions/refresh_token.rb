# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # Uniform seam entrypoint — renew the long-lived Threads user token before it
      # expires (~day 50 of 60), extending it ~60 more days (threads.md §4). GET
      # graph.threads.net/refresh_access_token. Returns token attrs to persist
      # (same shape as the other vendors' RefreshToken).
      class RefreshToken
        def self.call(...) = new(...).call

        def initialize(social_account, client: nil)
          @social_account = social_account
          @client = client || Vendors::Threads::Client.new(social_account)
        end

        def call
          result = @client.oauth_get(
            '/refresh_access_token',
            params: { grant_type: 'th_refresh_token', access_token: @social_account.user_access_token }
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
