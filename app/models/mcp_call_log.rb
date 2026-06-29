# frozen_string_literal: true

# Append-only audit record of a single MCP tools/call. Written by
# Mcp::CallAudit. Side-effecting / billable tool calls are always persisted;
# reads are sampled to the logger instead (see Mcp::CallAudit).
class McpCallLog < ApplicationRecord
  belongs_to :user,      optional: true
  belongs_to :workspace, optional: true

  scope :recent, -> { order(created_at: :desc) }
end
