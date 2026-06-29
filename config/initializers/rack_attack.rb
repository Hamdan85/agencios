# frozen_string_literal: true

# Throttling for the MCP connector surface only — the open DCR endpoint, the
# token endpoint, and the MCP RPC endpoint. Scoped to these paths so the SPA /
# JSON API are untouched. Disabled in test to keep request specs deterministic.
class Rack::Attack
  # The open Dynamic Client Registration endpoint: bound abuse hard.
  throttle("oauth/register/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/oauth/register"
  end

  # Token exchange / refresh.
  throttle("oauth/token/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/oauth/token"
  end

  # MCP RPC: per access token when present (so one noisy connector can't starve
  # others), else per IP. The token is only an identifier here — not validated.
  throttle("mcp/token", limit: 300, period: 1.minute) do |req|
    next unless req.path == "/mcp" && req.post?

    bearer = req.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (.+)\z/i, 1]
    bearer ? Digest::SHA256.hexdigest(bearer) : req.ip
  end

  self.throttled_responder = lambda do |_req|
    [429, { "Content-Type" => "application/json" },
     [{ error: "Too many requests. Please slow down." }.to_json]]
  end
end

Rack::Attack.enabled = !Rails.env.test?
