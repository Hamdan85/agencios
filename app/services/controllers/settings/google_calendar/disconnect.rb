# frozen_string_literal: true

module Controllers
  module Settings
    module GoogleCalendar
      # Clears the workspace's Google Calendar tokens, severing the integration.
      # Meetings created after disconnect fall back to stub events (local IDs
      # only, no real Calendar event or Meet link).
      class Disconnect < Controllers::Base
        def call
          setting = workspace.setting || Setting.create!(workspace: workspace)
          setting.update!(
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
