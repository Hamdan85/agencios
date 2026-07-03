# frozen_string_literal: true

module Controllers
  module Projects
    class Update < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        project = workspace.projects.find(@params[:id])
        attrs = project_params
        # Moving a project to another client only lands on an active one.
        find_active_client!(attrs[:client_id]) if attrs[:client_id].present? && attrs[:client_id].to_s != project.client_id.to_s
        project.update!(attrs)
        { project: serialize(project, ProjectSerializer) }
      end

      private

      def project_params
        @params.require(:project).permit(
          :client_id, :name, :description, :color, :status,
          :starts_on, :ends_on, :budget_cents
        )
      end
    end
  end
end
