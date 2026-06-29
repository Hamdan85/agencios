# frozen_string_literal: true

# Audit trail for MCP tool invocations. Append-only: one row per tools/call,
# capturing who (user + oauth application), where (workspace), what (tool +
# scope), and the outcome. Reads are sampled to logs; cost/side-effect tools
# always land here (see Mcp::CallAudit).
class CreateMcpCallLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_call_logs do |t|
      t.references :user,        null: true, foreign_key: true
      t.references :workspace,   null: true, foreign_key: true
      t.bigint     :oauth_application_id
      t.string     :tool_name,   null: false
      t.string     :scope
      t.boolean    :ok,          null: false, default: true
      t.string     :error_class
      t.datetime   :created_at,  null: false
    end

    add_index :mcp_call_logs, :tool_name
    add_index :mcp_call_logs, %i[workspace_id created_at]
    add_index :mcp_call_logs, :oauth_application_id
  end
end
