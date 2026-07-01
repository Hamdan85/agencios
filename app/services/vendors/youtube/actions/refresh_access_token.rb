# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Refreshes the access token (§4.3). Google returns a fresh access_token +
      # expires_in but NO new refresh_token, so we keep the existing refresh_token.
      # On invalid_grant the client raises AuthenticationError → caller flips the
      # account to needs_reauth.
      #
      # Returns persistable attrs: { user_access_token:, token_expires_at: }.
      class RefreshAccessToken
        def self.call(...) = new(...).call

        def initialize(social_account)
          @social_account = social_account
        end

        def call
          body = Vendors::Youtube::Client.new.refresh(refresh_token: @social_account.refresh_token)

          {
            user_access_token: body['access_token'],
            token_expires_at: expires_at(body['expires_in'])
          }
        end

        private

        def expires_at(seconds)
          seconds.present? ? Time.current + seconds.to_i.seconds : nil
        end
      end
    end
  end
end
