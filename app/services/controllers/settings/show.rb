# frozen_string_literal: true

module Controllers
  module Settings
    class Show < Base
      def call
        Payload.new(Settings.ensure_setting!(workspace)).call
      end
    end
  end
end
