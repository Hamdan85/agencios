# frozen_string_literal: true

module Controllers
  module Tickets
    class Reorder < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:id])
        Operations::Tickets::Reorder.call(ticket: ticket, position: @params.require(:position))
        { ticket: serialize(ticket.reload, TicketCardSerializer) }
      end
    end
  end
end
