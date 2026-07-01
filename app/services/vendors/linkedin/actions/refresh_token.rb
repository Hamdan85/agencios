# frozen_string_literal: true

module Vendors
  module Linkedin
    module Actions
      # Uniform seam entrypoint: re-exchange the refresh token for a fresh
      # 60-day access token (programmatic refresh tokens are partner-gated; absent
      # them, the caller must re-run the 3-legged flow).
      # POST /oauth/v2/accessToken (grant_type=refresh_token)
      # See docs/integrations/linkedin.md §4.
      class RefreshToken
        def self.call(...) = new(...).call

        def initialize(social_account)
          @social_account = social_account
        end

        # Returns { user_access_token:, refresh_token:, token_expires_at: }.
        def call
          client = Vendors::Linkedin::Client.new(social_account: @social_account)
          body = client.token_request(
            grant_type: 'refresh_token',
            refresh_token: @social_account.refresh_token,
            client_id: client.client_id,
            client_secret: client.client_secret
          )

          {
            user_access_token: body['access_token'],
            # A refresh keeps the original refresh-token TTL; LinkedIn may or may
            # not return a new refresh_token — fall back to the existing one.
            refresh_token: body['refresh_token'] || @social_account.refresh_token,
            token_expires_at: token_expires_at(body['expires_in'])
          }
        end

        private

        def token_expires_at(seconds)
          return nil if seconds.blank?

          Time.current + seconds.to_i.seconds
        end
      end
    end
  end
end
