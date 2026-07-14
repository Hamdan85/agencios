# frozen_string_literal: true

module Controllers
  module Approvals
    # "Pedir aprovação" (from Produção) and "Reenviar link" (from Aprovação) are the
    # same button at two points in the funnel. Sending a ticket to the client IS
    # moving it into Aprovação — the transition fires the request. Once it's already
    # there, a resend is just the request again, with no transition to make.
    class RequestApproval < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:id])
        if ticket.approval?
          Operations::Approvals::RequestApproval.call(ticket: ticket, sent_by: user)
        else
          Operations::Tickets::ChangeStatus.call(ticket, 'approval', user: user)
        end
        { ok: true }
      end
    end
  end
end
