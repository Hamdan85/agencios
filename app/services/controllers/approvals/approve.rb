# frozen_string_literal: true

module Controllers
  module Approvals
    class Approve < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:id])
        Operations::Approvals::ApproveAll.call(ticket: ticket, actor: user)
        { ok: true }
      end
    end
  end
end
