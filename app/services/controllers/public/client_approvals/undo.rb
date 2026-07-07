# frozen_string_literal: true

module Controllers
  module Public
    module ClientApprovals
      # The client undoes a just-made approval within the undo window. Returns the
      # refreshed queue (the ticket reappears as pending).
      class Undo < Controllers::Base
        def initialize(client:, params:)
          @client = client
          @params = params
        end

        def call
          ticket = @client.tickets.find(@params[:ticket_id])
          Operations::Approvals::Undo.call(ticket: ticket, actor: @client)
          Show.new(client: @client).call
        end
      end
    end
  end
end
