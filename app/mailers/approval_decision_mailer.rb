# frozen_string_literal: true

# Notifies the responsible team member that the client made an approval decision
# on a ticket (approved, or requested changes). Agency-branded like the rest.
class ApprovalDecisionMailer < ApplicationMailer
  def decided(ticket:, decision:, recipient:, creative: nil, feedback: nil)
    @ticket = ticket
    @decision = decision.to_s
    @approved = @decision == 'approved'
    @creative = creative
    @feedback = feedback
    @project = ticket.project
    @client = ticket.project.client
    @brand_workspace = ticket.workspace
    @url = app_url("/tickets/#{ticket.id}")
    subject = @approved ? "Cliente aprovou — #{@project.name}" : "Cliente pediu ajustes — #{@project.name}"
    mail(to: recipient.email, subject: subject)
  end
end
