# frozen_string_literal: true

# Ticket-centric notifications to internal members.
class TicketMailer < ApplicationMailer
  # A ticket was assigned to `assignee`. `actor` is who made the assignment.
  def assigned(ticket:, assignee:, actor: nil)
    @ticket = ticket
    @assignee = assignee
    @actor_name = actor&.display_name
    @project = ticket.project
    @ticket_url = "#{SystemConfig.app_host}/tickets/#{ticket.id}"
    with_recipient_locale(assignee) do
      mail(to: assignee.email, subject: I18n.t('mailers.ticket.assigned.subject', title: ticket.display_title))
    end
  end
end
