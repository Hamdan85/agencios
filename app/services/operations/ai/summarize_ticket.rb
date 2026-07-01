# frozen_string_literal: true

module Operations
  module Ai
    # Builds the status-aware system prompt, calls Anthropic, writes
    # ticket.ai_summaries[status], and broadcasts summary_ready.
    class SummarizeTicket < Operations::Base
      def initialize(ticket:, status: nil)
        @ticket = ticket
        @status = (status || ticket.status).to_s
      end

      def call
        builder = Prompts::TicketSummary.new(
          workspace: @ticket.workspace, client: @ticket.project.client,
          ticket: @ticket, status: @status
        )
        summary = AiAdapter.complete(
          builder, max_tokens: 400, operation: 'summarize_ticket', subject: @ticket
        ).to_s.strip

        summaries = @ticket.ai_summaries.merge(@status => summary)
        @ticket.update!(ai_summaries: summaries)

        Broadcaster.ticket(@ticket, 'summary_ready', status: @status, summary: summary)
        summary
      end
    end
  end
end
