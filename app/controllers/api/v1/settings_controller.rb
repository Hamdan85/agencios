# frozen_string_literal: true

module Api
  module V1
    class SettingsController < BaseController
      def show   = render_ok(Controllers::Settings::Show.call)
      def update = render_ok(Controllers::Settings::Update.call(params:))

      def brand_assets = render_ok(Controllers::Settings::UpdateBrandAssets.call(params:))
    end
  end
end
