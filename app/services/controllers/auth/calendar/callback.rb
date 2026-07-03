# frozen_string_literal: true

module Controllers
  module Auth
    module Calendar
      # Verifies the signed state (carrying user_id), exchanges the authorization
      # code for tokens, and persists them on the USER — calendars are personal,
      # each member connects their own from the account page. Called by
      # Auth::CalendarController#callback — a browser-facing request, so Current
      # is not set; the user is resolved from state.
      class Callback
        def self.call(...) = new(...).call

        def initialize(code:, state:)
          @code  = code
          @state = state
        end

        def call
          data = verify_state!
          raise Operations::Errors::Invalid, 'code missing' if @code.blank?

          user  = User.find(data['user_id'])
          token = Vendors::Google::Actions::ExchangeCode.call(
            code: @code, redirect_uri: Calendar.redirect_uri
          )

          user.update!(
            google_access_token: token['access_token'],
            google_refresh_token: token['refresh_token'].presence || user.google_refresh_token,
            google_calendar_connected_at: Time.current
          )
        end

        private

        def verify_state!
          Rails.application.message_verifier(Calendar::STATE_PURPOSE).verify(@state.to_s)
        rescue ActiveSupport::MessageVerifier::InvalidSignature,
               ActiveSupport::MessageEncryptor::InvalidMessage
          raise Operations::Errors::Invalid, 'State inválido ou expirado.'
        end
      end
    end
  end
end
