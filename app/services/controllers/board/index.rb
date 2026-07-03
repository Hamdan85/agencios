# frozen_string_literal: true

module Controllers
  module Board
    # Columns keyed by status with serialized cards, filtered per the board's
    # filter set (project, client, assignee, channel, creative type).
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        { columns: columns, workspace_id: workspace.id }
      end

      private

      def columns
        grouped = filtered_scope.board_ordered.group_by(&:status)
        Ticket::WORKFLOW.map do |status|
          tickets = grouped[status.to_s] || []
          {
            status: status.to_s,
            label: Ticket::STATUS_LABELS[status.to_s],
            tickets: serialize_collection(tickets, TicketCardSerializer)
          }
        end
      end

      def filtered_scope
        # `in_live_project` drops tickets of archived campaigns/clients — the
        # board is active work only; their history stays on the client/project pages.
        scope = workspace.tickets.active.in_live_project
                         .includes(:project, :assignee, :subtasks, :creatives, :autopilot_runs)
        ::Tickets::Filters.apply(scope, @params)
      end
    end
  end
end
