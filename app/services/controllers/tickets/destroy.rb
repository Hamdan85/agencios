# frozen_string_literal: true

module Controllers
  module Tickets
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        ticket = workspace.tickets.find(@params[:id])
        ticket.update!(archived_at: Time.current)
        { message: 'Ticket arquivado.' }
      end
    end
  end
end
