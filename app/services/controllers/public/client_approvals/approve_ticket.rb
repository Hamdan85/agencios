# frozen_string_literal: true

module Controllers
  module Public
    module ClientApprovals
      # The client approves ONE media-type slot of a ticket, choosing the winning
      # option (`creative_id`). Returns the refreshed queue so the deck reflects the
      # decision (and drops the ticket once every slot is decided).
      class ApproveTicket < Controllers::Base
        def initialize(client:, params:)
          @client = client
          @params = params
        end

        def call
          ticket = @client.tickets.find(@params[:ticket_id])
          Operations::Approvals::ApproveSlot.call(
            ticket: ticket,
            creative_type: @params[:creative_type],
            chosen_creative_id: @params[:creative_id],
            actor: @client
          )
          Show.new(client: @client).call
        end
      end
    end
  end
end
