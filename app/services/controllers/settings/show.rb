# frozen_string_literal: true

module Controllers
  module Settings
    class Show < Base
      def call
        Payload.new(setting).call
      end

      private

      def setting
        workspace.setting || Setting.create!(workspace: workspace)
      end
    end
  end
end
