# frozen_string_literal: true

module Controllers
  module Reports
    # Renders a ready report deck to a branded PDF for download/print. Scoped to
    # the active workspace through its project; returns the binary bytes + a
    # human-friendly filename the controller streams back.
    class Pdf < Base
      def initialize(params:)
        @params = params
      end

      def call
        report = ProjectReport.joins(:project)
                              .where(projects: { workspace_id: workspace.id })
                              .find(@params[:id])
        authorize!(report.project, :show?)
        raise ActiveRecord::RecordNotFound, 'Relatório ainda não está pronto.' unless report.status_ready?

        {
          bytes: Operations::Reports::RenderPdf.call(report:),
          filename: "relatorio-#{report.project.name.parameterize}.pdf"
        }
      end
    end
  end
end
