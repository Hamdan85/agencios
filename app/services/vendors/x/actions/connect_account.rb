# frozen_string_literal: true

module Vendors
  module X
    module Actions
      # Uniform seam entrypoint: exchange the OAuth code (with the PKCE verifier),
      # fetch the account identity, and return the attributes to persist on a
      # SocialAccount. The seam's Operations::Social::ConnectAccount persists it.
      #
      # NOTE: X is OAuth 2.0 PKCE, so the caller must pass the `code_verifier` it
      # persisted from BuildAuthorizeUrl alongside the `code`.
      # See docs/integrations/x-twitter.md §4–§5.
      class ConnectAccount
        def self.call(...) = new(...).call

        def initialize(code:, workspace:, redirect_uri:, code_verifier:)
          @code = code
          @workspace = workspace
          @redirect_uri = redirect_uri
          @code_verifier = code_verifier
        end

        def call
          token = Vendors::X::Actions::ExchangeCode.call(
            code: @code, redirect_uri: @redirect_uri, code_verifier: @code_verifier
          )
          access_token = token["access_token"]

          identity = Vendors::X::Actions::FetchUser.call(access_token: access_token)

          {
            provider: :x,
            external_user_id: identity[:id],
            username: identity[:username],
            user_access_token: access_token,
            refresh_token: token["refresh_token"],
            token_expires_at: expires_at(token["expires_in"]),
            scopes: scopes_array(token["scope"])
          }
        end

        private

        def expires_at(seconds)
          return nil if seconds.blank?

          Time.current + seconds.to_i.seconds
        end

        def scopes_array(scope)
          return [] if scope.blank?

          scope.split(/\s+/).reject(&:blank?)
        end
      end
    end
  end
end
