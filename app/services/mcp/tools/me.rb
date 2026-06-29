# frozen_string_literal: true

module Mcp
  module Tools
    # Account-level identity: the authenticated user and the workspaces they
    # belong to. No workspace argument.
    class Me < BaseTool
      tool_name "me"
      description "The authenticated user and the workspaces they belong to. Read-only."

      def self.mcp_spec
        Mcp::Registry::Spec.new(
          name: "me", service: "Controllers::Me::Show", description: description,
          scope: :read, workspace_scoped: false, params_arg: false,
          side_effect: false, destructive: false, cost: false
        )
      end

      def call(**_args)
        require_scope!(:read)
        Mcp::ToolContext.for_user(user: actor) { Controllers::Me::Show.call }
      end
    end
  end
end
