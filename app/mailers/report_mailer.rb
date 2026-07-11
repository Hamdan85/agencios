# frozen_string_literal: true

# Client-facing campaign report — the agency delivering the finalized audit deck
# to its client as a branded PDF. Agency-branded (@brand_workspace).
class ReportMailer < ApplicationMailer
  def deck(report:, recipients:, pdf_bytes:)
    @report = report
    @project = report.project
    @client = @project.client
    @brand_workspace = report.workspace
    @url = app_url("/portal/#{@client.approval_token!}")

    with_recipient_locale(@client) do
      attachments[I18n.t('api.reports.filename', project: @project.name.parameterize)] = {
        mime_type: 'application/pdf',
        content: pdf_bytes
      }
      mail(to: recipients, subject: I18n.t('mailers.report.deck.subject', project: @project.name))
    end
  end
end
