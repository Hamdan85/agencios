# frozen_string_literal: true

module Auth
  # Handles the Google Calendar OAuth callback. This is a browser-facing
  # request (not an API call), so it renders a minimal inline page that
  # posts a postMessage to the opener popup and closes itself.
  class CalendarController < ActionController::Base
    def callback
      Controllers::Auth::Calendar::Callback.call(
        code: params[:code], state: params[:state]
      )
      render 'auth/calendar/connected', layout: false, locals: { error: nil }
    rescue Operations::Errors::Invalid => e
      Rails.logger.warn("[Auth::Calendar] #{e.message}")
      render 'auth/calendar/connected', layout: false, locals: { error: 'state' }
    rescue StandardError => e
      Rails.logger.warn("[Auth::Calendar] #{e.class}: #{e.message}")
      render 'auth/calendar/connected', layout: false, locals: { error: 'calendar' }
    end
  end
end
