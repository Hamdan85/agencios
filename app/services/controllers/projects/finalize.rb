# frozen_string_literal: true

module Controllers
  module Projects
    class Finalize < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        project = workspace.projects.find(@params[:id])
        report = Operations::Projects::Finalize.call(project: project, user: user)
        {
          project: serialize(project, ProjectSerializer),
          report: report && serialize(report, ProjectReportSerializer)
        }
      end
    end
  end
end
