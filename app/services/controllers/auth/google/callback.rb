# frozen_string_literal: true

module Controllers
  module Auth
    module Google
      # Verifies the signed `state`, completes the OAuth code exchange, and returns
      # the resolved User plus the validated return path. The controller owns the
      # cookie session lifecycle (start_new_session_for) and the browser redirect.
      class Callback < Controllers::Base
        def initialize(code:, state:)
          @code = code
          @state = state
        end

        def call
          data = verify_state!
          raise Operations::Errors::Invalid, 'Autorização do Google ausente.' if @code.blank?

          user = Operations::Auth::Google::SignIn.call(
            code: @code, redirect_uri: Google.redirect_uri
          )
          { user: user, return_to: Google.safe_return_to(data['r'] || data[:r]) }
        end

        private

        def verify_state!
          Rails.application.message_verifier(Google::STATE_PURPOSE).verify(@state.to_s)
        rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveSupport::MessageEncryptor::InvalidMessage
          raise Operations::Errors::Invalid, 'Sessão de login expirada. Tente novamente.'
        end
      end
    end
  end
end
