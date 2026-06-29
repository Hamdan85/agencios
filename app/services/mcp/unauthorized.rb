# frozen_string_literal: true

module Mcp
  # Bearer token missing / expired / revoked. The MCP controller answers with a
  # 401 + WWW-Authenticate challenge directly; this exists for callers that
  # prefer to raise.
  class Unauthorized < StandardError; end
end
