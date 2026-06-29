# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /tickets/:id/ai_action — run the AI action scoped to the ticket's
    # current status (idea synthesis in ideation, scope builder in scoping,
    # contextual summary otherwise).
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
        when "ideation"
          Operations::Ai::SynthesizeIdea.call(ticket: ticket)
        when "scoping"
          { subtasks: serialize_collection(Operations::Ai::BuildScope.call(ticket: ticket), SubtaskSerializer) }
        else
          Operations::Ai::SummarizeTicket.call(ticket: ticket, status: ticket.status)
        end
      end
    end
  end
end
