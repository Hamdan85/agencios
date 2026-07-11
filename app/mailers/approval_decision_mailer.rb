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
    with_recipient_locale(recipient) do
      subject = @approved ? I18n.t('mailers.approval_decision.decided.subject_approved', project: @project.name) :
                            I18n.t('mailers.approval_decision.decided.subject_changes', project: @project.name)
      mail(to: recipient.email, subject: subject)
    end
  end
end
