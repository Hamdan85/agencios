# frozen_string_literal: true

module Vendors
  module Threads
    module Actions
      # Uniform seam entrypoint — exchange the OAuth code for a long-lived Threads
      # user token, resolve identity, and return the SocialAccount attrs to persist.
      # The seam's Operations::Social::ConnectAccount persists the hash. No Facebook
      # Page: the token lives in `user_access_token`, the Threads user id in
      # `external_user_id` (the publish target). (threads.md §4)
      class ConnectAccount
        def self.call(...) = new(...).call

        def initialize(code:, workspace:, redirect_uri:, client: nil)
          @code = code
          @workspace = workspace
          @redirect_uri = redirect_uri
          @client = client || Vendors::Threads::Client.new
        end

        def call
          short = ExchangeCodeForToken.call(
            code: @code, redirect_uri: @redirect_uri, client: @client
          )
          long = ExchangeLongLivedToken.call(
            short_lived_token: short['access_token'], client: @client
          )
          user_token = long['access_token']
          profile = GetProfile.call(access_token: user_token, client: @client)

          threads_user_id = (profile['id'] || short['user_id']).to_s

          {
            provider: :threads,
            external_user_id: threads_user_id,
            username: profile['username'],
            avatar_url: profile['threads_profile_picture_url'],
            user_access_token: user_token,
            token_expires_at: expiry_from(long['expires_in']),
            scopes: AuthorizeUrl::SCOPES,
            status: :connected
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
