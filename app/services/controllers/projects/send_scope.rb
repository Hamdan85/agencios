# frozen_string_literal: true

module Controllers
  module Projects
    class SendScope < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        project = workspace.projects.find(@params[:id])
        Operations::Projects::SendScope.call(project: project, recipients: recipients)
        { ok: true }
      end

      private

      def recipients
        Array(@params[:recipients]).map(&:to_s)
      end
    end
  end
end
