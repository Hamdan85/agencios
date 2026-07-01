# frozen_string_literal: true

module Mcp
  # JSON-RPC 2.0 dispatch for the MCP protocol over our own Streamable HTTP
  # endpoint (Mcp::ServerController). Stateless: one instance per HTTP request,
  # carrying the already-authenticated actor + granted scopes.
  class Dispatcher
    # Protocol revisions we can speak. We echo the client's requested version
    # when supported, else negotiate down to the latest we know.
    SUPPORTED_PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze
    LATEST_PROTOCOL_VERSION = "2025-06-18"

    SERVER_INFO = { name: "agencios", version: "1.0.0" }.freeze

    def initialize(actor:, granted_scopes:, application_id: nil)
      @actor = actor
      @granted_scopes = granted_scopes
      @application_id = application_id
    end

    # Returns a JSON-RPC response Hash, or nil for notifications (no `id`).
    def handle(request)
      return nil unless request.is_a?(Hash)

      id = request["id"]
      case request["method"]
      when "initialize"            then result(id, initialize_result(request["params"] || {}))
      when "ping"                  then result(id, {})
      when "tools/list"            then result(id, { tools: tool_list })
      when "tools/call"            then handle_call(request["params"] || {}, id)
      when %r{\Anotifications/}    then nil # client → server notices need no reply
      when nil                     then nil # a response/notification echoed back
      else error(id, -32_601, "Method not found: #{request['method']}")
      end
    end

    private

    def initialize_result(params)
      requested = params["protocolVersion"]
      version = SUPPORTED_PROTOCOL_VERSIONS.include?(requested) ? requested : LATEST_PROTOCOL_VERSION
      {
        protocolVersion: version,
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO
      }
    end

    def tool_list
      Catalog.tool_classes.map do |klass|
        spec = klass.mcp_spec
        {
          name: klass.tool_name,
          description: klass.description.to_s,
          inputSchema: klass.input_schema_to_json || { type: "object", properties: {}, required: [] },
          annotations: annotations_for(klass, spec)
        }
      end
    end

    def annotations_for(klass, spec)
      {
        title: klass.tool_name.tr("_", " ").capitalize,
        readOnlyHint: !(spec.side_effect || spec.cost),
        destructiveHint: spec.destructive
      }
    end

    def handle_call(params, id)
      name = params["name"]
      return error(id, -32_602, "Invalid params: missing tool name") if name.blank?

      klass = Catalog.find(name)
      return error(id, -32_602, "Unknown tool: #{name}") unless klass

      spec = klass.mcp_spec
      args = symbolize(params["arguments"] || {})
      tool = klass.new(actor: @actor, granted_scopes: @granted_scopes)

      begin
        value, = tool.call_with_schema_validation!(**args)
        audit(spec, workspace_id: tool.invoked_workspace_id, ok: true)
        result(id, tool_success(value))
      rescue StandardError => e
        audit(spec, workspace_id: tool.invoked_workspace_id, ok: false, error_class: e.class.name)
        result(id, tool_failure(error_message(e)))
      end
    end

    # --- Tool result envelopes (MCP tools/call result shape) -----------------
    def tool_success(value)
      {
        content: [{ type: "text", text: stringify(value) }],
        structuredContent: value.is_a?(Hash) ? value : { result: value },
        isError: false
      }
    end

    def tool_failure(message)
      { content: [{ type: "text", text: message }], isError: true }
    end

    def stringify(value)
      value.is_a?(String) ? value : JSON.pretty_generate(value)
    end

    # Translate domain errors into clear, non-leaky tool messages.
    def error_message(err)
      case err
      when Mcp::ForbiddenScope,
           Mcp::ToolContext::WorkspaceNotFound,
           Mcp::ToolContext::NotAMember,
           Mcp::ToolContext::PlanRequired,
           Operations::Errors::Forbidden,
           Operations::Errors::Invalid,
           Operations::Errors::InvalidTransition,
           Operations::Errors::SeatLimitReached,
           Operations::Errors::BillingRequired
        err.message
      when Pundit::NotAuthorizedError
        "Your role in this workspace does not permit this action."
      when ActiveRecord::RecordNotFound
        "Record not found."
      when ActiveRecord::RecordInvalid
        err.record.errors.full_messages.to_sentence.presence || err.message
      when FastMcp::Tool::InvalidArgumentsError
        "Invalid arguments: #{err.message}"
      else
        Rails.logger.error("[mcp] unexpected tool error: #{err.class}: #{err.message}")
        "The tool failed: #{err.class}."
      end
    end

    def audit(spec, ok:, workspace_id: nil, error_class: nil)
      Mcp::CallAudit.record(
        user: @actor, workspace_id: workspace_id, application_id: @application_id,
        tool_name: spec.name, scope: spec.scope, ok: ok,
        persist: spec.side_effect || spec.cost, error_class: error_class
      )
    end

    def result(id, value)
      { jsonrpc: "2.0", id: id, result: value }
    end

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    def symbolize(hash)
      return {} unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(k, v), out|
        out[k.to_sym] = v.is_a?(Hash) ? symbolize(v) : v
      end
    end
  end
end
