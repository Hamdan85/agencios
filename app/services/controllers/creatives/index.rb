# frozen_string_literal: true

module Controllers
  module Creatives
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        ticket = workspace.tickets.find(@params[:ticket_id])
        { creatives: serialize_collection(ticket.creatives.order(created_at: :desc), CreativeSerializer) }
      end
    end
  end
end
