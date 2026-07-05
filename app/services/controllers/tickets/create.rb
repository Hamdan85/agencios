# frozen_string_literal: true

module Controllers
  module Tickets
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_seat_compliance!
        ticket = Operations::Tickets::Create.call(workspace: workspace, user: user, params: ticket_params)
        { ticket: serialize(ticket, TicketSerializer) }
      end

      private

      def ticket_params
        @params.require(:ticket).permit(
          :project_id, :title, :assignee_id, :priority, :due_date, :scheduled_at,
          :creative_type, channels: [], fields: {}
        )
      end
    end
  end
end
