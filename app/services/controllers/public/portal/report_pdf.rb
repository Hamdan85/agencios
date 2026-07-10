# frozen_string_literal: true

module Controllers
  module Public
    module Portal
      # The finalized campaign report, rendered to the same branded PDF the agency
      # can download — served to the client through their portal token. Returns
      # the binary bytes + filename the controller streams back.
      class ReportPdf < Base
        def call
          project = project!
          report = project.latest_report
          raise ActiveRecord::RecordNotFound, 'Relatório indisponível.' unless report&.status_ready?

          {
            bytes: Operations::Reports::RenderPdf.call(report:),
            filename: "relatorio-#{project.name.parameterize}.pdf"
          }
        end
      end
    end
  end
end
