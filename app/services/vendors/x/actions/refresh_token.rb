# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # Step D — refresh. Returns a NEW access_token AND a NEW (rotated)
      # refresh_token — the rotated refresh_token MUST be persisted each time or
      # the account locks out.
      # POST https://api.x.com/2/oauth2/token (grant_type=refresh_token)
      # See docs/integrations/x-twitter.md §4.
      #
      # Uniform seam entrypoint: accepts a SocialAccount and returns the updated
      # token attrs.
      class RefreshToken
        def self.call(...) = new(...).call

        def initialize(social_account)
          @social_account = social_account
        end

        # Returns { user_access_token:, refresh_token:, token_expires_at: }.
        def call
          client = Vendors::X::Client.new(social_account: @social_account)
          body = client.token_request(
            grant_type: "refresh_token",
            refresh_token: @social_account.refresh_token,
            client_id: client.client_id
          )

          {
            user_access_token: body["access_token"],
            refresh_token: body["refresh_token"] || @social_account.refresh_token,
            token_expires_at: token_expires_at(body["expires_in"])
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
