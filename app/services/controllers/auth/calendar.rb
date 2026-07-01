# frozen_string_literal: true

module Controllers
  module Auth
    # Shared constants + helpers for the Google Calendar connect flow.
    # Start (authorize_url) lives in Controllers::Settings::GoogleCalendar::AuthorizeUrl;
    # the callback that stores the tokens lives in Calendar::Callback below.
    module Calendar
      STATE_PURPOSE = 'agencios:calendar_connect'
      STATE_TTL     = 10.minutes

      def self.redirect_uri = "#{SystemConfig.app_host}/auth/calendar/callback"
    end
  end
end
