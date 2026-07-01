# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Refreshes a connected account's access token (§4.3). Uniform seam entrypoint.
      #
      # CRITICAL (token rotation): the returned refresh_token MAY differ from the one
      # sent — the caller must overwrite BOTH access_token and refresh_token plus both
      # expiry timestamps. Refreshing also resets the 365-day refresh window.
      #
      # Returns persistable attrs:
      #   { user_access_token:, refresh_token:, token_expires_at:, refresh_token_expires_at:, scopes: }
      class RefreshToken
        def self.call(...) = new(...).call

        def initialize(social_account)
          @social_account = social_account
        end

        def call
          body = Vendors::TikTok::Client.new.refresh(refresh_token: @social_account.refresh_token)

          {
            user_access_token: body['access_token'],
            refresh_token: body['refresh_token'],
            token_expires_at: expires_at(body['expires_in']),
            refresh_token_expires_at: expires_at(body['refresh_expires_in']),
            scopes: scopes_from(body['scope'])
          }
        end

        private

        def expires_at(seconds)
          seconds.present? ? Time.current + seconds.to_i.seconds : nil
        end

        def scopes_from(scope)
          scope.to_s.split(',').map(&:strip).reject(&:empty?)
        end
      end
    end
  end
end
