# frozen_string_literal: true

module Controllers
  module Public
    module ClientApprovals
      # The client approves a whole ticket from the portal. Returns the refreshed
      # queue so the deck drops the decided item.
      class ApproveTicket < Controllers::Base
        def initialize(client:, params:)
          @client = client
          @params = params
        end

        def call
          ticket = @client.tickets.find(@params[:ticket_id])
          Operations::Approvals::ApproveTicket.call(ticket: ticket, actor: @client)
          Show.new(client: @client).call
        end
      end
    end
  end
end
