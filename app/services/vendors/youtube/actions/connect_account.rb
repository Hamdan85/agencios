# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Uniform seam entrypoint — exchanges the OAuth code, resolves the channel id +
      # title via channels.list?mine=true (§4.2), and returns SocialAccount attrs.
      #
      # Column mapping (per docs/integrations/youtube.md §5, reusing shared columns):
      #   channel id    -> channel_id (UC...)
      #   channel title -> channel_title
      #   access_token  -> user_access_token (encrypted)
      #   refresh_token -> refresh_token (encrypted)
      #   expires_in    -> token_expires_at
      #   scope         -> scopes
      class ConnectAccount
        def self.call(...) = new(...).call

        def initialize(code:, workspace:, redirect_uri:)
          @code = code
          @workspace = workspace
          @redirect_uri = redirect_uri
        end

        def call
          token = Vendors::Youtube::Actions::ExchangeCode.call(
            code: @code, redirect_uri: @redirect_uri
          )

          channel = resolve_channel(token["access_token"])

          {
            provider: :youtube,
            channel_id: channel["id"],
            channel_title: channel.dig("snippet", "title"),
            username: channel.dig("snippet", "title"),
            external_user_id: channel["id"],
            user_access_token: token["access_token"],
            refresh_token: token["refresh_token"],
            token_expires_at: expires_at(token["expires_in"]),
            scopes: scopes_from(token["scope"]),
            status: :connected
          }
        end

        private

        # channels.list?part=id,snippet&mine=true — bind tokens to the chosen channel.
        def resolve_channel(access_token)
          body = Vendors::Youtube::Client
                 .new(access_token: access_token)
                 .list_channels(part: "id,snippet")
          Array(body["items"]).first || {}
        end

        def expires_at(seconds)
          seconds.present? ? Time.current + seconds.to_i.seconds : nil
        end

        def scopes_from(scope)
          scope.to_s.split(" ").reject(&:empty?)
        end
      end
    end
  end
end
