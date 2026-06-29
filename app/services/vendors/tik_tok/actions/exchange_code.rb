# frozen_string_literal: true

module Vendors
  module TikTok
    module Actions
      # Exchanges an OAuth authorization code for access + refresh tokens (§4.2).
      # Returns the raw token response hash:
      #   { access_token:, expires_in:, refresh_token:, refresh_expires_in:, open_id:, scope:, token_type: }
      class ExchangeCode
        def self.call(...) = new(...).call

        def initialize(code:, redirect_uri:, code_verifier: nil)
          @code = code
          @redirect_uri = redirect_uri
          @code_verifier = code_verifier
        end

        def call
          Vendors::TikTok::Client.new.exchange_code(
            code: @code, redirect_uri: @redirect_uri, code_verifier: @code_verifier
          )
        end
      end
    end
  end
end
