# frozen_string_literal: true

# Client-facing content approval — the agency asking its client to review the
# ticket's creatives via a login-less link. Agency-branded (@brand_workspace).
class ApprovalMailer < ApplicationMailer
  def review(ticket:, recipients:)
    @ticket = ticket
    @client = ticket.project.client
    @project = ticket.project
    @brand_workspace = ticket.workspace
    # One link per client — the central lists every campaign; deep-link straight
    # to this campaign's approvals tab.
    @url = app_url("/portal/#{@client.approval_token!}?campanha=#{@project.id}&aba=aprovacoes")
    mail(to: recipients, subject: "Aprove o conteúdo — #{@project.name}")
  end
end
