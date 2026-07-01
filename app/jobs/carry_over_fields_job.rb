# frozen_string_literal: true

# Pre-fills the fields of the status a ticket just advanced into, from all the
# context produced in the earlier funnel stages. Enqueued by ChangeStatus on a
# forward transition; never overwrites fields the team already filled.
class CarryOverFieldsJob < ApplicationJob
  queue_as :default

  def perform(ticket_id, status = nil)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket

    Operations::Tickets::CarryOver.call(ticket: ticket, status: status || ticket.status)
  end
end
