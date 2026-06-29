# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # Uniform seam entrypoint. X's authorize URL is built via PKCE, so this
      # delegates to BuildAuthorizeUrl and returns just the URL string (the seam
      # contract). When the caller needs the code_verifier/state to persist for
      # the callback, call BuildAuthorizeUrl directly.
      # See docs/integrations/x-twitter.md §4.
      class AuthorizeUrl
        def self.call(...) = new(...).call

        def initialize(workspace:, redirect_uri:, state:)
          @workspace = workspace
          @redirect_uri = redirect_uri
          @state = state
        end

        # Returns the authorize URL string.
        def call
          Vendors::X::Actions::BuildAuthorizeUrl.call(
            redirect_uri: @redirect_uri, state: @state
          ).fetch(:url)
        end
      end
    end
  end
end
