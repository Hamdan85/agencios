# frozen_string_literal: true

module Operations
  module Reports
    # Emails the finalized campaign report to the client as a branded PDF. Renders
    # (or reuses) the report's PDF, attaches it to ReportMailer.deck, delivers to
    # the client's e-mail, and stamps `sent_to_client_at`.
    #
    # No-ops honestly (returns false) when the report is not ready or the client
    # has no e-mail — never fabricates a send.
    class SendToClient < Operations::Base
      def initialize(report:, sent_by: nil)
        @report = report
        @project = report.project
        @sent_by = sent_by
      end

      def call
        return false unless @report.status_ready?

        recipients = Array(@project.client&.email).compact_blank
        return false if recipients.empty?

        pdf_bytes = Operations::Reports::RenderPdf.call(report: @report)
        ReportMailer.deck(report: @report, recipients: recipients, pdf_bytes: pdf_bytes).deliver_later
        @report.update!(sent_to_client_at: Time.current)
        true
      end
    end
  end
end
