# frozen_string_literal: true

module Controllers
  module Tickets
    # GET /api/v1/tickets/ids — the ids of every ticket matching the current
    # filter set (same filters + `view` as Index), without pagination. Powers the
    # "select all" action so it spans the whole result set, not just loaded pages.
    class Ids < Base
      def initialize(params:)
        @params = params
      end

      def call
        # Filters may join `projects`, so qualify the column to avoid "ambiguous
        # column id".
        ids = ::Tickets::Filters.apply(base_scope, @params).pluck("tickets.id")
        { ids: ids }
      end

      private

      def base_scope
        scope = workspace.tickets
        case @params[:view].to_s
        when "archived" then scope.archived
        when "all"      then scope
        else                 scope.active
        end
      end
    end
  end
end
