# frozen_string_literal: true

module Mcp
  module Tools
    # Base class for every MCP tool. Built on FastMcp::Tool purely for its
    # Dry::Schema argument DSL + JSON-Schema generation (`input_schema_to_json`);
    # the transport is our own Mcp::ServerController, not fast-mcp's.
    #
    # A tool is a THIN adapter: it checks the OAuth scope, opens the tenant
    # context for the requested workspace, and calls the matching `Controllers::*`
    # service — inheriting Pundit authorization and serializers unchanged.
    #
    # The dispatcher instantiates a tool with the already-authenticated `actor`
    # (the OAuth resource owner) and the token's `granted_scopes`.
    class BaseTool < FastMcp::Tool
      attr_reader :actor, :granted_scopes, :invoked_workspace_id

      def initialize(headers: {}, actor: nil, granted_scopes: [])
        super(headers: headers)
        @actor = actor
        @granted_scopes = Array(granted_scopes).map(&:to_s)
        @invoked_workspace_id = nil
      end

      private

      # OAuth scope gate (defense-in-depth on top of Pundit's role gate inside
      # the service). Raises Mcp::ForbiddenScope, mapped to a tool error.
      def require_scope!(scope)
        return if granted_scopes.include?(scope.to_s)

        raise Mcp::ForbiddenScope, scope
      end

      def run_workspace_service(service, workspace_ref, params)
        Mcp::ToolContext.for(user: actor, workspace_ref: workspace_ref) do
          @invoked_workspace_id = Current.workspace&.id
          invoke(service, params)
        end
      end

      def run_account_service(service, params)
        Mcp::ToolContext.for_user(user: actor) do
          invoke(service, params)
        end
      end

      def invoke(service, params)
        klass = service.is_a?(String) ? service.constantize : service
        return klass.call if params.nil?

        klass.call(params: ActionController::Parameters.new(params.deep_stringify_keys))
      end
    end
  end
end
