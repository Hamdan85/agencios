# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Uniform seam entrypoint — exchanges the OAuth code, resolves account identity,
      # and returns the attrs to persist on a SocialAccount. The seam's
      # Operations::Social::ConnectAccount persists the returned hash.
      #
      # Column mapping (per docs/integrations/tiktok.md §5.2, reusing shared columns):
      #   open_id            -> external_user_id
      #   union_id           -> union_id
      #   access_token       -> user_access_token (encrypted)
      #   refresh_token      -> refresh_token (encrypted)
      #   expires_in         -> token_expires_at
      #   refresh_expires_in -> refresh_token_expires_at
      #   scope              -> scopes
      #   display_name/username/avatar_url from user info
      class ConnectAccount
        def self.call(...) = new(...).call

        def initialize(code:, workspace:, redirect_uri:)
          @code = code
          @workspace = workspace
          @redirect_uri = redirect_uri
        end

        def call
          token = Vendors::TikTok::Actions::ExchangeCode.call(
            code: @code, redirect_uri: @redirect_uri
          )

          # Fetch identity with the freshly-minted access token (no persisted account yet).
          user = fetch_user(token['access_token'])

          {
            provider: :tiktok,
            external_user_id: token['open_id'],
            union_id: user['union_id'],
            username: user['username'],
            display_name: user['display_name'],
            avatar_url: user['avatar_url'],
            user_access_token: token['access_token'],
            refresh_token: token['refresh_token'],
            token_expires_at: expires_at(token['expires_in']),
            refresh_token_expires_at: expires_at(token['refresh_expires_in']),
            scopes: scopes_from(token['scope']),
            status: :connected
          }
        end

        private

        def fetch_user(access_token)
          body = Vendors::TikTok::Client
                 .new(access_token: access_token)
                 .user_info(fields: Vendors::TikTok::Actions::FetchUserInfo::DEFAULT_FIELDS.join(','))
          body.dig('data', 'user') || {}
        rescue Vendors::Base::Error
          # Profile/stats fields may be unscoped pre-audit — degrade to id-only identity.
          {}
        end

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
