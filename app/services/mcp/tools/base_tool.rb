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

      def run_workspace_service(service, workspace_ref, params, media: nil)
        Mcp::ToolContext.for(user: actor, workspace_ref: workspace_ref) do
          @invoked_workspace_id = Current.workspace&.id
          result = invoke(service, params)
          next result unless media

          Mcp::ToolResult.new(data: result, blocks: media_blocks(media, result, params))
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

      # Resolve the creatives a media-bearing tool wants to render (inside the
      # tenant context) and turn their attachments into MCP content blocks.
      # Media is best-effort: a failure here must never fail the tool call.
      def media_blocks(media, result, params)
        Mcp::Media.blocks_for(media.call(result, params))
      rescue StandardError => e
        Rails.logger.warn("[mcp] media rendering failed: #{e.class}: #{e.message}")
        []
      end
    end
  end
end
