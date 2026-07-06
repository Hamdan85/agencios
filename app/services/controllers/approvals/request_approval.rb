# frozen_string_literal: true

module Controllers
  module Approvals
    class RequestApproval < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:id])
        Operations::Approvals::RequestApproval.call(ticket: ticket, sent_by: user)
        { ok: true }
      end
    end
  end
end
