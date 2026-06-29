# frozen_string_literal: true

module Mcp
  module Tools
    # Account-level entry point: the workspaces (agencies/teams) this connection
    # can act on, with the slug to pass as the `workspace` argument of every
    # other tool. Claude should call this first.
    class ListWorkspaces < BaseTool
      tool_name "list_workspaces"
      description "List the workspaces (teams) you can operate, with the slug to use as the " \
                  "`workspace` argument of every other tool, plus your role in each. Read-only. " \
                  "Call this first."

      def self.mcp_spec
        Mcp::Registry::Spec.new(
          name: "list_workspaces", service: nil, description: description,
          scope: :read, workspace_scoped: false, params_arg: false,
          side_effect: false, destructive: false, cost: false
        )
      end

      def call(**_args)
        require_scope!(:read)
        Mcp::ToolContext.for_user(user: actor) do
          {
            workspaces: actor.workspaces.order(:created_at).map do |workspace|
              membership = actor.membership_for(workspace)
              { id: workspace.id, slug: workspace.slug, name: workspace.name, role: membership&.role }
            end
          }
        end
      end
    end
  end
end
