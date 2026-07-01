# frozen_string_literal: true

module Controllers
  module Projects
    class Start < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        project = workspace.projects.find(@params[:id])
        Operations::Projects::Start.call(project: project, user: user)
        { project: serialize(project, ProjectSerializer) }
      end
    end
  end
end
