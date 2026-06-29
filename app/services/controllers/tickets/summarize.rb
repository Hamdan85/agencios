# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /tickets/:id/summarize — regenerate the status summary now.
    class Summarize < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:id])
        summary = Operations::Ai::SummarizeTicket.call(ticket: ticket, status: ticket.status)
        { status: ticket.status, summary: summary }
      end
    end
  end
end
