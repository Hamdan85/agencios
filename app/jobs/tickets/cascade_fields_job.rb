# frozen_string_literal: true

module Tickets
  # Re-derives a ticket's LATER stages after an earlier one was edited (see
  # Operations::Tickets::CascadeFields). Enqueued by the field-update controller
  # and by the manual "Atualizar com IA" job.
  #
  # Debounce: a `token` (the ticket's updated_at at enqueue time) collapses a burst
  # of autosaves into a single downstream regeneration — a stale job whose token no
  # longer matches the ticket's current updated_at bails, because the LATEST edit
  # queued its own job that WILL match. A nil token means "run unconditionally"
  # (used by the single, deliberate manual-refill path).
  class CascadeFieldsJob < ApplicationJob
    queue_as :default

    def perform(ticket_id, from_status, token = nil)
      ticket = Ticket.find_by(id: ticket_id)
      return unless ticket
      return if token.present? && ticket.updated_at.utc.iso8601(6) != token

      Operations::Tickets::CascadeFields.call(ticket: ticket, from_status: from_status)
    end
  end
end
