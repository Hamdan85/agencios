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

    attachments["relatorio-#{@project.name.parameterize}.pdf"] = {
      mime_type: 'application/pdf',
      content: pdf_bytes
    }
    mail(to: recipients, subject: "Relatório da campanha — #{@project.name}")
  end
end
