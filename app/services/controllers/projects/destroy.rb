# frozen_string_literal: true

module Controllers
  module Projects
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        workspace.projects.find(@params[:id]).destroy!
        { message: I18n.t('api.projects.removed') }
      end
    end
  end
end
