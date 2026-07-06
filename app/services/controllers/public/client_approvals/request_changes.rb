# frozen_string_literal: true

module Controllers
  module Public
    module ClientApprovals
      # The client requests changes on one creative of a ticket. Returns the
      # refreshed queue.
      class RequestChanges < Controllers::Base
        def initialize(client:, params:)
          @client = client
          @params = params
        end

        def call
          ticket = @client.tickets.find(@params[:ticket_id])
          creative = ticket.creatives.find(@params[:creative_id])
          Operations::Approvals::RequestChanges.call(
            creative: creative, feedback: @params[:feedback].to_s, actor: @client
          )
          Show.new(client: @client).call
        end
      end
    end
  end
end
