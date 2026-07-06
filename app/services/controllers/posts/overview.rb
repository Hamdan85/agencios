# frozen_string_literal: true

module Controllers
  module Posts
    # The analytics header of the posts hub: workspace-scoped KPIs + breakdowns
    # over the (optionally filtered) window. Read-only for the team, hidden from
    # client guests.
    class Overview < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        { overview: Operations::Analytics::PostsOverview.call(workspace: workspace, filters: filters) }
      end

      private

      def filters
        @params.permit(:client_id, :project_id, :from, :to, providers: [], creative_types: []).to_h
      end
    end
  end
end
