# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Uniform seam entrypoint — builds the Google consent URL (§4.1).
      # Scopes (§3): upload + readonly + yt-analytics.readonly (the minimal set for
      # "upload + read own analytics"). All three are Sensitive scopes.
      class AuthorizeUrl
        SCOPES = %w[
          https://www.googleapis.com/auth/youtube.upload
          https://www.googleapis.com/auth/youtube.readonly
          https://www.googleapis.com/auth/yt-analytics.readonly
        ].freeze

        def self.call(...) = new(...).call

        def initialize(workspace:, redirect_uri:, state:)
          @workspace = workspace
          @redirect_uri = redirect_uri
          @state = state
        end

        def call
          Vendors::Youtube::Client.new.authorize_url(
            scope: SCOPES.join(' '),
            redirect_uri: @redirect_uri,
            state: @state
          )
        end
      end
    end
  end
end
