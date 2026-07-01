# frozen_string_literal: true

module Controllers
  module Settings
    module GoogleCalendar
      # Builds the Google Calendar OAuth consent URL for the current workspace.
      # Signs a state token carrying the workspace_id so the callback can
      # look up the right Setting without a live session.
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
            { workspace_id: workspace.id, n: SecureRandom.hex(16) },
            expires_in: Auth::Calendar::STATE_TTL
          )
        end
      end
    end
  end
end
