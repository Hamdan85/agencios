# frozen_string_literal: true

module Tickets
  # Runs the per-phase "Atualizar campos com IA" action OFF the request. The Claude
  # call is too slow to hold an HTTP connection open (it was 502-ing), so the
  # frontend fires-and-forgets: it shimmers the current stage's fields, and this
  # job broadcasts on `ticket_<id>` when the rewrite settles so the UI stops the
  # shimmer and adopts the new values.
  #
  #   ai_fill_started { status }              → fields go into shimmer
  #   ai_fill_done    { status, filled: [..] }→ shimmer off, adopt new fields
  #   ai_fill_failed  { status }              → shimmer off, surface the error
  class AiFillJob < ApplicationJob
    queue_as :default

    def perform(ticket_id, instruction: nil)
      ticket = Ticket.find_by(id: ticket_id)
      return unless ticket

      status = ticket.status
      Broadcaster.ticket(ticket, 'ai_fill_started', status: status)

      result = run(ticket, instruction)

      Broadcaster.ticket(ticket, 'ai_fill_done', status: status, filled: Array(result.is_a?(Hash) ? result[:filled] : nil))
    rescue StandardError => e
      Rails.logger.warn("[Tickets::AiFillJob] ticket ##{ticket_id}: #{e.class}: #{e.message}")
      Broadcaster.ticket(ticket, 'ai_fill_failed', status: ticket&.status) if ticket
    end

    private

    # The read-only monitoring/done stages have no fields — there the action
    # (re)generates the contextual summary instead (mirrors the old sync path).
    def run(ticket, instruction)
      case ticket.status
      when 'published', 'done'
        Operations::Ai::SummarizeTicket.call(ticket: ticket, status: ticket.status)
      else
        Operations::Ai::FillFields.call(ticket: ticket, instruction: instruction)
      end
    end
  end
end
