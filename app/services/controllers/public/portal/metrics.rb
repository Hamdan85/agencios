# frozen_string_literal: true

module Controllers
  module Public
    module Portal
      # Campaign-scoped analytics for the client — reuses the workspace analytics
      # aggregator filtered to this one project. Pure read; the real-time layer
      # (PortalChannel) tells the client when to refetch.
      class Metrics < Base
        def call
          project = project!
          overview = Operations::Analytics::PostsOverview.call(
            workspace: @client.workspace,
            filters: { project_id: project.id, from: @params[:from], to: @params[:to] }
          )
          {
            campaign: { id: project.id, name: project.name, color: project.color },
            overview: overview
          }
        end
      end
    end
  end
end
