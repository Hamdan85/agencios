# frozen_string_literal: true

module Controllers
  module Reports
    # POST /api/v1/reports/:id/send — the team manually e-mails the finalized
    # report to the client (the manual counterpart of the GO-mode auto-send).
    class Send < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        report = ProjectReport.joins(:project)
                              .where(projects: { workspace_id: workspace.id })
                              .find(@params[:id])
        authorize!(report.project, :show?)

        sent = Operations::Reports::SendToClient.call(report: report, sent_by: user)
        raise Operations::Errors::Invalid, 'O relatório ainda não está pronto ou o cliente não tem e-mail cadastrado.' unless sent

        { report: serialize(report, ProjectReportSerializer) }
      end
    end
  end
end
