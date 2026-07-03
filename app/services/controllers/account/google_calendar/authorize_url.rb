# frozen_string_literal: true

module Controllers
  module Account
    module GoogleCalendar
      # Builds the Google Calendar OAuth consent URL for the CURRENT USER —
      # meetings are user-level, each person connects their own calendar.
      # Signs a state token carrying the user_id so the callback can persist
      # the tokens on the right User without a live session.
      class AuthorizeUrl < Controllers::Base
        def call
          { url: Vendors::Google::Actions::CalendarAuthorizeUrl.call(
            redirect_uri: Auth::Calendar.redirect_uri,
            state: signed_state
          ) }
        end

        private

        def signed_state
          Rails.application.message_verifier(Auth::Calendar::STATE_PURPOSE).generate(
            { user_id: user.id, n: SecureRandom.hex(16) },
            expires_in: Auth::Calendar::STATE_TTL
          )
        end
      end
    end
  end
end
