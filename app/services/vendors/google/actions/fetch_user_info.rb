# frozen_string_literal: true

module Vendors
  module Google
    module Actions
      # Fetches the OpenID Connect profile for a Google access token. Returns the
      # raw hash ({ "sub", "email", "email_verified", "name", "picture", ... }).
      class FetchUserInfo
        def self.call(...) = new(...).call

        def initialize(access_token:)
          @access_token = access_token
        end

        def call
          Vendors::Google::Oauth.new.fetch_userinfo(access_token: @access_token)
        end
      end
    end
  end
end
