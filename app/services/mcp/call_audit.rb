# frozen_string_literal: true

module Mcp
  # Records MCP tool invocations. Side-effecting / billable calls are persisted
  # to `mcp_call_logs` for audit; read-only calls are logged at info level to
  # avoid table bloat. Never raises — auditing must not break a tool call.
  module CallAudit
    module_function

    def record(user:, workspace_id:, application_id:, tool_name:, scope:, ok:, persist:, error_class: nil)
      if persist
        McpCallLog.create!(
          user_id: user&.id,
          workspace_id: workspace_id,
          oauth_application_id: application_id,
          tool_name: tool_name,
          scope: scope.to_s,
          ok: ok,
          error_class: error_class,
          created_at: Time.current
        )
      else
        Rails.logger.info(
          "[mcp] tool=#{tool_name} user=#{user&.id} workspace=#{workspace_id} " \
          "scope=#{scope} ok=#{ok}#{" error=#{error_class}" if error_class}"
        )
      end
    rescue StandardError => e
      Rails.logger.error("[mcp] audit failed for #{tool_name}: #{e.class}: #{e.message}")
    end
  end
end
