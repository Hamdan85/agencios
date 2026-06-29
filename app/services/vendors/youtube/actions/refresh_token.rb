# frozen_string_literal: true

module Vendors
  module Youtube
    module Actions
      # Uniform seam alias for RefreshAccessToken (the seam calls RefreshToken across
      # every vendor). Returns { user_access_token:, token_expires_at: }.
      class RefreshToken
        def self.call(...) = new(...).call

        def initialize(social_account)
          @social_account = social_account
        end

        def call
          Vendors::Youtube::Actions::RefreshAccessToken.call(@social_account)
        end
      end
    end
  end
end
