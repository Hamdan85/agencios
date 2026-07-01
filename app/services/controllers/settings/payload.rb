# frozen_string_literal: true

module Controllers
  module Settings
    # Shared settings payload (the Setting record + the workspace's brand fields),
    # built by both Show and Update.
    class Payload < Base
      def initialize(setting)
        @setting = setting
      end

      def call
        {
          setting: serialize(@setting, SettingSerializer),
          workspace: workspace_brand
        }
      end

      private

      def workspace_brand
        {
          name: workspace.name,
          brand_voice: workspace.brand_voice,
          default_handle: workspace.default_handle,
          brand_primary_color: workspace.brand_primary_color,
          brand_secondary_color: workspace.brand_secondary_color,
          logo_url: blob_url(workspace.logo)
        }
      end

      def blob_url(attachment)
        return nil unless attachment.attached?

        Rails.application.routes.url_helpers.rails_blob_url(attachment, host: SystemConfig.app_host)
      rescue StandardError
        nil
      end
    end
  end
end
