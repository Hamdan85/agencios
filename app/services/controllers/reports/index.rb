# frozen_string_literal: true

module Controllers
  module Reports
    # Reports for one project (newest first). Nested route: the project scopes it.
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        project = workspace.projects.find(@params[:project_id])
        authorize!(project, :show?)
        { reports: serialize_collection(project.reports.recent, ProjectReportSummarySerializer) }
      end
    end
  end
end
