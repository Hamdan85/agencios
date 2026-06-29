# frozen_string_literal: true

module Api
  module V1
    class SettingsController < BaseController
      def show   = render_ok(Controllers::Settings::Show.call)
      def update = render_ok(Controllers::Settings::Update.call(params:))
    end
  end
end
