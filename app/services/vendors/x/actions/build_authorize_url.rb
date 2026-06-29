# frozen_string_literal: true

require "securerandom"
require "digest"
require "base64"

module Vendors
  module X
    module Actions
      # Step A+B — generate the PKCE pair and build the authorize URL.
      # GET https://x.com/i/oauth2/authorize
      #
      # Returns { url:, code_verifier:, state: } — the caller MUST persist
      # code_verifier + state (session/Redis) keyed to the workspace until the
      # callback, to complete the exchange and the CSRF check.
      # See docs/integrations/x-twitter.md §4.
      class BuildAuthorizeUrl
        def self.call(...) = new(...).call

        SCOPES = %w[tweet.read tweet.write users.read media.write offline.access].freeze

        def initialize(redirect_uri:, state: nil, scopes: SCOPES, code_verifier: nil)
          @redirect_uri = redirect_uri
          @state = state || SecureRandom.urlsafe_base64(24)
          @scopes = scopes
          @code_verifier = code_verifier || SecureRandom.urlsafe_base64(64)
        end

        def call
          client = Vendors::X::Client.new
          query = URI.encode_www_form(
            response_type: "code",
            client_id: client.client_id,
            redirect_uri: @redirect_uri,
            scope: @scopes.join(" "),
            state: @state,
            code_challenge: code_challenge,
            code_challenge_method: "S256"
          )

          {
            url: "#{Vendors::X::Client::AUTHORIZE_URL}?#{query}",
            code_verifier: @code_verifier,
            state: @state
          }
        end

        private

        # BASE64URL(SHA256(code_verifier)), unpadded.
        def code_challenge
          digest = Digest::SHA256.digest(@code_verifier)
          Base64.urlsafe_encode64(digest, padding: false)
        end
      end
    end
  end
end
