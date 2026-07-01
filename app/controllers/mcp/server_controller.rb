# frozen_string_literal: true

module Mcp
  # The remote MCP endpoint (Streamable HTTP). Claude connects here as a custom
  # connector. POST carries JSON-RPC requests; we authenticate the OAuth bearer
  # token, resolve the user, and dispatch to Mcp::Dispatcher.
  #
  # On a missing/invalid token we answer 401 with a WWW-Authenticate header that
  # points at our protected-resource metadata — that is the signal that makes
  # Claude start the OAuth + Dynamic Client Registration flow.
  class ServerController < ActionController::API
    # Browsers (e.g. MCP Inspector) need these origins allowed for DNS-rebinding
    # safety; Claude connects server-side and usually sends no Origin.
    ALLOWED_ORIGIN_HOSTS = %w[claude.ai claude.com localhost 127.0.0.1 [::1]].freeze

    before_action :set_cors_headers
    before_action :handle_preflight
    before_action :validate_origin!
    before_action :authenticate_token!

    # POST /mcp — a single JSON-RPC request/notification or a batch array.
    def handle
      payload = parse_payload
      return render(json: rpc_error(nil, -32_700, 'Parse error'), status: :ok) if payload.nil?

      dispatcher = Mcp::Dispatcher.new(
        actor: @actor, granted_scopes: @granted_scopes, application_id: @application_id
      )

      if payload.is_a?(Array)
        responses = payload.filter_map { |req| dispatcher.handle(req) }
        responses.empty? ? head(:accepted) : render(json: responses)
      else
        response_body = dispatcher.handle(payload)
        response_body.nil? ? head(:accepted) : render(json: response_body)
      end
    end

    # GET /mcp — we don't offer a standalone server→client SSE stream.
    def stream
      response.set_header('Allow', 'POST, DELETE')
      head :method_not_allowed
    end

    # DELETE /mcp — session termination (we're stateless: nothing to drop).
    def terminate
      head :no_content
    end

    private

    def parse_payload
      JSON.parse(request.raw_post)
    rescue JSON::ParserError, TypeError
      nil
    end

    # ── Auth ────────────────────────────────────────────────────────────
    def authenticate_token!
      access = bearer_access_token
      return challenge!('invalid_token') unless access&.accessible?

      @actor = User.find_by(id: access.resource_owner_id)
      return challenge!('invalid_token') unless @actor

      @granted_scopes = access.scopes.to_a
      @application_id = access.application_id
    end

    def bearer_access_token
      token = request.authorization.to_s[/\ABearer (.+)\z/i, 1]
      token && Doorkeeper::AccessToken.by_token(token)
    end

    def challenge!(error)
      metadata_url = "#{request.base_url}/.well-known/oauth-protected-resource"
      response.set_header(
        'WWW-Authenticate',
        %(Bearer resource_metadata="#{metadata_url}", error="#{error}", scope="read write")
      )
      render json: rpc_error(nil, -32_001, 'Unauthorized'), status: :unauthorized
    end

    def rpc_error(id, code, message)
      { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
    end

    # ── CORS / Origin (DNS-rebinding protection) ─────────────────────────
    def set_cors_headers
      origin = request.headers['Origin']
      return if origin.blank?

      response.set_header('Access-Control-Allow-Origin', origin)
      response.set_header('Vary', 'Origin')
      response.set_header('Access-Control-Allow-Methods', 'POST, GET, DELETE, OPTIONS')
      response.set_header('Access-Control-Allow-Headers',
                          'Authorization, Content-Type, Mcp-Session-Id, MCP-Protocol-Version')
      response.set_header('Access-Control-Expose-Headers', 'WWW-Authenticate, Mcp-Session-Id')
    end

    def handle_preflight
      head(:no_content) if request.request_method == 'OPTIONS'
    end

    def validate_origin!
      origin = request.headers['Origin']
      return if origin.blank? # server-to-server (Claude) sends no Origin

      host = begin
        URI.parse(origin).host
      rescue URI::InvalidURIError
        nil
      end
      allowed = host && ALLOWED_ORIGIN_HOSTS.any? { |h| host == h || host.end_with?(".#{h}") }
      head(:forbidden) unless allowed
    end
  end
end
