# frozen_string_literal: true

module Controllers
  module Projects
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        authorize!(Project, :create?)
        require_seat_compliance!
        project = Operations::Projects::Create.call(project_params)
        { project: serialize(project, ProjectSerializer) }
      end

      private

      def project_params
        permitted = @params.require(:project).permit(
          :client_id, :name, :description, :color, :status,
          :starts_on, :ends_on, :budget_cents
        )
        raw_settings = @params.dig(:project, :settings)
        permitted[:settings] = ::Tickets::ProjectSettings.sanitize(raw_settings.to_unsafe_h) if raw_settings.present?
        permitted
      end
    end
  end
end
