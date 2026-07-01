# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /tickets/:id/ai_action — the per-phase "Gerar com IA" action. For every
    # editable funnel stage it FILLS the current status's fields from all prior
    # work (Operations::Ai::FillFields). On the read-only monitoring/done stages
    # it (re)generates the contextual summary instead.
    class AiAction < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:id])
        { result: run(ticket) }
      end

      private

      def run(ticket)
        case ticket.status
        when 'published', 'done'
          Operations::Ai::SummarizeTicket.call(ticket: ticket, status: ticket.status)
        else
          Operations::Ai::FillFields.call(ticket: ticket)
        end
      end
    end
  end
end
