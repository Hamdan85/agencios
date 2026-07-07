# frozen_string_literal: true

class DraftRetrospectiveJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket

    Operations::Ai::DraftRetrospective.call(ticket: ticket)
  end
end
