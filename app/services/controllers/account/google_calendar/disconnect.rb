# frozen_string_literal: true

module Controllers
  module Account
    module GoogleCalendar
      # Clears the current user's Google Calendar tokens, severing THEIR
      # integration. Meetings they create afterwards fall back to stub events
      # (local IDs only, no real Calendar event or Meet link).
      class Disconnect < Controllers::Base
        def call
          user.update!(
            google_access_token: nil,
            google_refresh_token: nil,
            google_calendar_connected_at: nil
          )
          {}
        end
      end
    end
  end
end
