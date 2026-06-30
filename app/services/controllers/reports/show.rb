# frozen_string_literal: true

module Controllers
  module Reports
    # A single report deck. Scoped to the active workspace through its project.
    class Show < Base
      def initialize(params:)
        @params = params
      end

      def call
        report = ProjectReport.joins(:project)
                              .where(projects: { workspace_id: workspace.id })
                              .find(@params[:id])
        authorize!(report.project, :show?)
        { report: serialize(report, ProjectReportSerializer) }
      end
    end
  end
end
