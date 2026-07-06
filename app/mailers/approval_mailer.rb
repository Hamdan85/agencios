# frozen_string_literal: true

# Client-facing content approval — the agency asking its client to review the
# ticket's creatives via a login-less link. Agency-branded (@brand_workspace).
class ApprovalMailer < ApplicationMailer
  def review(ticket:, recipients:)
    @ticket = ticket
    @client = ticket.project.client
    @project = ticket.project
    @brand_workspace = ticket.workspace
    @url = app_url("/aprovar/#{ticket.approval_token!}")
    mail(to: recipients, subject: "Aprove o conteúdo — #{@project.name}")
  end
end
