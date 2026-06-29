# frozen_string_literal: true

module Controllers
  module Projects
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Project, :create?)
        project = Operations::Projects::Create.call(project_params)
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
