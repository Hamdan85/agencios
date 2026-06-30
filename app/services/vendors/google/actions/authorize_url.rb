# frozen_string_literal: true

module Vendors
  module Google
    module Actions
      # Builds the Google consent URL for "Sign in with Google".
      class AuthorizeUrl
        def self.call(...) = new(...).call

        def initialize(redirect_uri:, state:)
          @redirect_uri = redirect_uri
          @state = state
        end

        def call
          Vendors::Google::Oauth.new.authorize_url(redirect_uri: @redirect_uri, state: @state)
        end
      end
    end
  end
end
