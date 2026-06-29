# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Uniform seam entrypoint — builds the Login Kit authorize URL (§4.1) the
      # user's browser is redirected to. Scopes are the recommended set for agencios
      # (§3): basic + profile + stats + publish + upload + list.
      class AuthorizeUrl
        SCOPES = %w[
          user.info.basic
          user.info.profile
          user.info.stats
          video.publish
          video.upload
          video.list
        ].freeze

        def self.call(...) = new(...).call

        def initialize(workspace:, redirect_uri:, state:)
          @workspace = workspace
          @redirect_uri = redirect_uri
          @state = state
        end

        def call
          Vendors::TikTok::Client.new.authorize_url(
            scope: SCOPES.join(","),
            redirect_uri: @redirect_uri,
            state: @state
          )
        end
      end
    end
  end
end
