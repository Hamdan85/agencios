# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /tickets/:id/advance — the single board move. Delegates to the
    # authoritative ChangeStatus operation, then returns the refreshed ticket.
    class Advance < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:id])
        Operations::Tickets::ChangeStatus.call(
          ticket, @params.require(:to_status),
          user: user, position: @params[:position]
        )
        Show.new(params: @params).call
      end
    end
  end
end
