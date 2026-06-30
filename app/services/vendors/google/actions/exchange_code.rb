# frozen_string_literal: true

module Vendors
  module Google
    module Actions
      # Exchanges the authorization code for tokens. Returns the raw token hash
      # ({ access_token:, expires_in:, scope:, token_type:, id_token: }).
      class ExchangeCode
        def self.call(...) = new(...).call

        def initialize(code:, redirect_uri:)
          @code = code
          @redirect_uri = redirect_uri
        end

        def call
          Vendors::Google::Oauth.new.exchange_code(code: @code, redirect_uri: @redirect_uri)
        end
      end
    end
  end
end
