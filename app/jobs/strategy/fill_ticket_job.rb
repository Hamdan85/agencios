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

      # Same events as the manual "Atualizar com IA" action, so a user who opens
      # the fresh ticket sees its fields shimmering (being written by the AI)
      # instead of a silently empty brief.
      Broadcaster.ticket(ticket, 'ai_fill_started', status: ticket.status)
      result = Operations::Ai::FillFields.call(ticket: ticket)
      Broadcaster.ticket(ticket, 'ai_fill_done', status: ticket.status,
                                                 filled: Array(result.is_a?(Hash) ? result[:filled] : nil))
      Operations::Ai::BuildScope.call(ticket: ticket)
    rescue Operations::Errors::Invalid => e
      # BuildScope bails when there's no context to plan from — non-fatal.
      Rails.logger.warn("[Strategy::FillTicketJob] ticket ##{ticket_id}: #{e.message}")
    rescue StandardError => e
      Rails.logger.warn("[Strategy::FillTicketJob] ticket ##{ticket_id}: #{e.class}: #{e.message}")
      Broadcaster.ticket(ticket, 'ai_fill_failed', status: ticket.status) if ticket
      raise
    end
  end
end
