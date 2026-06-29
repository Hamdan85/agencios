# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /api/v1/tickets/:id/unarchive — restore an archived ticket. Managers only.
    class Unarchive < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        ticket = workspace.tickets.find(@params[:id])
        Operations::Tickets::Archive.call(ticket, user: user, archived: false)
        Show.new(params: @params).call
      end
    end
  end
end
