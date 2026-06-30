# frozen_string_literal: true

module Controllers
  module Auth
    module Google
      # Builds the Google consent URL to redirect the browser to. A signed,
      # short-lived `state` token carries a CSRF nonce + the post-login return path
      # and is verified on the callback. The controller owns the actual redirect.
      class Start < Controllers::Base
        def initialize(return_to: nil)
          @return_to = Google.safe_return_to(return_to)
        end

        def call
          Vendors::Google::Actions::AuthorizeUrl.call(
            redirect_uri: Google.redirect_uri,
            state: signed_state
          )
        end

        private

        def signed_state
          Rails.application.message_verifier(Google::STATE_PURPOSE).generate(
            { n: SecureRandom.hex(16), r: @return_to }, expires_in: Google::STATE_TTL
          )
        end
      end
    end
  end
end
