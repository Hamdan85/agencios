# frozen_string_literal: true

module Api
  module V1
    class SettingsController < BaseController
      def show   = render_ok(Controllers::Settings::Show.call)
      def update = render_ok(Controllers::Settings::Update.call(params:))

      def google_calendar_authorize_url = render_ok(Controllers::Settings::GoogleCalendar::AuthorizeUrl.call)
      def google_calendar               = render_ok(Controllers::Settings::GoogleCalendar::Disconnect.call)
    end
  end
end
