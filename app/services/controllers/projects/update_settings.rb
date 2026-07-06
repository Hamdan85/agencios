# frozen_string_literal: true

module Controllers
  module Projects
    class UpdateSettings < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        project = workspace.projects.find(@params[:id])
        incoming = @params.fetch(:settings, {}).permit!.to_h
        project.update!(settings: ::Tickets::ProjectSettings.sanitize(incoming))
        { project: serialize(project, ProjectSerializer) }
      end
    end
  end
end
