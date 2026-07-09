# frozen_string_literal: true

module Controllers
  module Public
    module Portal
      # The finalized campaign report deck for the client. Returns the ready
      # report's document (same shape the internal report screen renders) or a
      # status marker when it is still generating / absent, so the frontend can
      # show an honest "gerando" / "sem relatório" state instead of a blank.
      class Report < Base
        def call
          project = project!
          report = project.latest_report
          return { status: 'none' } if report.nil?

          {
            status: report.status,
            report: report.status_ready? ? report_payload(report, project) : nil
          }
        end

        private

        def report_payload(report, project)
          {
            id: report.id,
            project_name: project.name,
            client_name: @client.name,
            period_start: report.period_start&.iso8601,
            period_end: report.period_end&.iso8601,
            overall_score: report.overall_score&.to_f,
            generated_at: report.generated_at&.iso8601,
            data: report.data
          }
        end
      end
    end
  end
end
