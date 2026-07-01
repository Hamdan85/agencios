# frozen_string_literal: true

module Controllers
  module Workspaces
    # POST /api/v1/workspace — create a brand-new workspace owned by the current
    # user (the canonical bootstrap runs in Operations::Workspaces::SetupForUser),
    # then point the session at it so the user lands inside the fresh tenant.
    #
    # Gated by the configurable per-user creation limit
    # (SystemConfig.max_workspaces_per_user, default 1).
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        unless user.can_create_workspace?
          raise Operations::Errors::Forbidden,
                'Você atingiu o limite de workspaces que pode criar.'
        end

        workspace = Operations::Workspaces::SetupForUser.call(user: user, name: workspace_name)

        # Land the session inside the freshly created workspace.
        Current.session.update!(workspace_id: workspace.id)
        Current.workspace = workspace
        Current.membership = workspace.memberships.find_by(user_id: user.id)

        # Return the full identity payload so the SPA refreshes user + active
        # workspace + the workspaces list in one round-trip.
        Controllers::Me::Show.call
      end

      private

      def workspace_name
        @params.dig(:workspace, :name).presence || @params[:name].presence
      end
    end
  end
end
