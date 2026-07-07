# frozen_string_literal: true

# Runs the flow-advancing side effect of a client approval AFTER the undo window,
# so an undo within the window leaves nothing to revert. OnFullyApproved itself
# guards on fully_approved? + production?, so a reverted approval is a no-op.
class OnFullyApprovedJob < ApplicationJob
  queue_as :default

  def perform(ticket_id)
    ticket = Ticket.find_by(id: ticket_id)
    return unless ticket

    Operations::Approvals::OnFullyApproved.call(ticket: ticket)
  end
end
