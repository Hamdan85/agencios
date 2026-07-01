# frozen_string_literal: true

module Controllers
  module Tickets
    # POST /tickets/:id/publish — the posting step action. Body:
    # { creative_id, mode: "immediate"|"scheduled", scheduled_at }. Builds the
    # posts and fires publishing; the ticket reaches "No ar" only on success.
    class Publish < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        ticket = workspace.tickets.find(@params[:id])
        Operations::Tickets::Publish.call(
          ticket: ticket,
          user: user,
          creative_id: @params[:creative_id],
          mode: @params[:mode] || "immediate",
          scheduled_at: @params[:scheduled_at]
        )
        Show.new(params: @params).call
      end
    end
  end
end
