# frozen_string_literal: true

module Controllers
  module Tickets
    # The global ticket list (rows), filterable by the same set as the board plus
    # a free-text search and an archive `view`. Paginated for infinite scroll.
    #
    #   view: "active" (default) | "archived" | "all"
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        scope = ::Tickets::Filters.apply(base_scope, @params).board_ordered
        records, meta = paginate(scope, @params, default_per: 30)
        {
          tickets: serialize_collection(records, TicketRowSerializer),
          meta: meta
        }
      end

      private

      def base_scope
        scope = workspace.tickets
                         .includes(:assignee, :subtasks, :creatives, project: :client)
        case @params[:view].to_s
        when 'archived' then scope.archived
        when 'all'      then scope
        # Default view is active work only — like the board, it hides tickets of
        # archived campaigns/clients. Use `view=all` (or the client/project page)
        # to reach an archived client's history.
        else                 scope.active.in_live_project
        end
      end
    end
  end
end
