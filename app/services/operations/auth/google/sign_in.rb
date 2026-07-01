# frozen_string_literal: true

module Operations
  module Auth
    module Google
      # Completes a "Sign in / Sign up with Google" flow: exchanges the auth code
      # for tokens, reads the OpenID profile, and resolves it to a User (creating
      # one + their first workspace on first sign-in). Returns the User. The cookie
      # session lifecycle stays an HTTP concern handled by the controller.
      class SignIn < Operations::Base
        def initialize(code:, redirect_uri:)
          @code = code
          @redirect_uri = redirect_uri
        end

        def call
          tokens  = Vendors::Google::Actions::ExchangeCode.call(code: @code, redirect_uri: @redirect_uri)
          profile = Vendors::Google::Actions::FetchUserInfo.call(access_token: tokens['access_token'])

          Operations::Users::FindOrCreateFromGoogle.call(
            uid: profile['sub'],
            email: profile['email'],
            name: profile['name'],
            email_verified: truthy?(profile['email_verified'])
          )
        end

        private

        # userinfo returns email_verified as a boolean, but some flows stringify it.
        def truthy?(value) = value == true || value.to_s == 'true'
      end
    end
  end
end
