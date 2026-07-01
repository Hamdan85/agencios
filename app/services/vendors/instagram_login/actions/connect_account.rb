# frozen_string_literal: true

module Vendors
  module InstagramLogin
    module Actions
      # Uniform seam entrypoint — exchange the OAuth code for a long-lived IG user
      # token, resolve the account identity, and return the SocialAccount attrs to
      # persist. The seam's Operations::Social::ConnectAccount persists the hash.
      #
      # Connects an Instagram Professional account WITHOUT a Facebook Page, so the
      # token lives in `user_access_token` and there is no `page_id`. Marked
      # `connection_type: :instagram_login` so the publish layer uses the
      # graph.instagram.com transport (instagram-login.md §4).
      class ConnectAccount
        def self.call(...) = new(...).call

        def initialize(code:, workspace:, redirect_uri:, client: nil)
          @code = code
          @workspace = workspace
          @redirect_uri = redirect_uri
          @client = client || Vendors::InstagramLogin::Client.new
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

          ig_user_id = (profile['user_id'] || short['user_id']).to_s

          {
            provider: :instagram,
            connection_type: :instagram_login,
            external_user_id: ig_user_id,
            ig_user_id: ig_user_id,
            username: profile['username'],
            avatar_url: profile['profile_picture_url'],
            user_access_token: user_token,
            page_id: nil,
            page_access_token: nil,
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
