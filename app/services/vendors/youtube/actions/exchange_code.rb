# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Exchanges the authorization code for tokens (§4.2). Returns the raw token hash:
      #   { access_token:, expires_in:, refresh_token:, scope:, token_type: }
      # (refresh_token present only with access_type=offline + prompt=consent).
      class ExchangeCode
        def self.call(...) = new(...).call

        def initialize(code:, redirect_uri:)
          @code = code
          @redirect_uri = redirect_uri
        end

        def call
          Vendors::Youtube::Client.new.exchange_code(code: @code, redirect_uri: @redirect_uri)
        end
      end
    end
  end
end
