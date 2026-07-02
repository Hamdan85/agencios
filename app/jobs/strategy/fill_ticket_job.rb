# frozen_string_literal: true

module Strategy
  # Fills a freshly-created plan ticket's ideation brief and production checklist
  # with AI, one ticket at a time. Enqueued by Operations::Strategy::Apply as each
  # card is materialized — the heavy per-ticket generation happens at CREATION, not
  # during planning. Each op broadcasts on `ticket_<id>`, so the real row updates
  # live in the table.
  class FillTicketJob < ApplicationJob
    queue_as :default

    def perform(ticket_id)
      ticket = Ticket.find_by(id: ticket_id)
      return unless ticket

      Operations::Ai::FillFields.call(ticket: ticket)
      Operations::Ai::BuildScope.call(ticket: ticket)
    rescue Operations::Errors::Invalid => e
      # BuildScope bails when there's no context to plan from — non-fatal.
      Rails.logger.warn("[Strategy::FillTicketJob] ticket ##{ticket_id}: #{e.message}")
    end
  end
end
