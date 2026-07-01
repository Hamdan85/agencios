# frozen_string_literal: true

module Controllers
  module Workspaces
    # POST /api/v1/workspace/switch — re-point the session at another workspace
    # the user belongs to, and refresh the resolved tenant in Current.
    class Switch < Base
      def initialize(params:)
        @params = params
      end

      def call
        target = user.workspaces.find_by(id: @params[:workspace_id])
        raise ActiveRecord::RecordNotFound, 'Workspace não encontrado.' unless target

        Current.session.update!(workspace_id: target.id)
        Current.workspace = target
        Current.membership = target.memberships.find_by(user_id: user.id)

        { workspace: serialize(target, WorkspaceSerializer) }
      end
    end
  end
end
