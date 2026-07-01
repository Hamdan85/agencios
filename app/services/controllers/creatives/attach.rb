# frozen_string_literal: true

module Controllers
  module Creatives
    # POST /tickets/:ticket_id/creatives/attach — link an existing, unassigned
    # Studio creative to this ticket (body: { creative_id }).
    class Attach < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:ticket_id])
        creative = workspace.creatives.find(@params.require(:creative_id))
        authorize!(creative, :attach?)

        creative = Operations::Creatives::AttachToTicket.call(ticket: ticket, creative: creative)
        { creative: serialize(creative, CreativeSerializer) }
      end
    end
  end
end
