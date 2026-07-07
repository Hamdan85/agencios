# frozen_string_literal: true

module Controllers
  module Settings
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        record = Settings.ensure_setting!(workspace)
        record.update!(setting_params)
        workspace.update!(workspace_params) if workspace_params.present?
        Payload.new(record).call
      end

      private

      def setting_params
        @params.fetch(:setting, {}).permit(:brand_tone, :auto_publish_default, preferences: {})
      end

      def workspace_params
        @params.fetch(:workspace, {}).permit(
          :name, :brand_voice, :default_handle,
          :brand_primary_color, :brand_secondary_color
        )
      end
    end
  end
end
