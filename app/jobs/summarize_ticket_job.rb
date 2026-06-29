# frozen_string_literal: true

class SummarizeTicketJob < ApplicationJob
  queue_as :default

  def perform(ticket_id, status = nil)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket

    Operations::Ai::SummarizeTicket.call(ticket: ticket, status: status || ticket.status)
  end
end
