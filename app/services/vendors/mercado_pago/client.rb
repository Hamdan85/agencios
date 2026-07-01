# frozen_string_literal: true

module Vendors
  module MercadoPago
    # Low-level Mercado Pago REST API wrapper (Brazil client-billing: Pix-first,
    # boleto, card, hosted Checkout Pro links, OAuth). Raw HTTP only — no domain
    # logic, no DB writes. Built on Vendors::Base's Faraday plumbing.
    #
    # Auth: every API call carries `Authorization: Bearer <ACCESS_TOKEN>`.
    #   - Single-tenant default: the platform's app-level access token from
    #     credentials (mercado_pago.access_token, ENV MERCADO_PAGO_ACCESS_TOKEN).
    #   - Multi-tenant (marketplace): the agency's own OAuth access token, stored
    #     encrypted on `workspace.setting.mercadopago_access_token`. When a
    #     workspace is passed and has connected its MP account, that token wins.
    #
    # See docs/integrations/mercado-pago.md.
    class Client < Vendors::Base
      BASE = "https://api.mercadopago.com"

      attr_reader :workspace

      # Whether the platform-level token is configured — the single-tenant
      # default every workspace rides on unless it's connected its own account.
      # Lets the frontend show "send payment link" affordances without a
      # per-workspace OAuth connection (see Setting#mercadopago_connected? for
      # that narrower, marketplace-only check).
      def self.platform_configured?
        Rails.application.credentials.dig(:mercado_pago, :access_token).present? ||
          ENV["MERCADO_PAGO_ACCESS_TOKEN"].present?
      end

      # Pass a workspace to prefer its connected OAuth token (marketplace), or an
      # explicit access_token (e.g. the OAuth token-exchange step itself, which
      # authenticates with client_id/client_secret rather than a Bearer token).
      def initialize(workspace: nil, access_token: nil)
        @workspace = workspace
        @access_token = access_token
      end

      # The Bearer token used for API calls. A workspace that has connected its
      # own MP account (OAuth) uses its token; otherwise the platform token.
      def access_token
        @access_token ||= workspace_access_token || platform_access_token
      end

      # The platform's app-level Mercado Pago access token (backend Bearer).
      def platform_access_token
        require_credential!(
          credential(:mercado_pago, :access_token, env: "MERCADO_PAGO_ACCESS_TOKEN"),
          "mercado_pago.access_token"
        )
      end

      # OAuth application identifier (marketplace connect / token exchange).
      def client_id
        require_credential!(
          credential(:mercado_pago, :client_id, env: "MERCADO_PAGO_CLIENT_ID"),
          "mercado_pago.client_id"
        )
      end

      # OAuth application secret (marketplace connect / token exchange).
      def client_secret
        require_credential!(
          credential(:mercado_pago, :client_secret, env: "MERCADO_PAGO_CLIENT_SECRET"),
          "mercado_pago.client_secret"
        )
      end

      # POST /v1/payments — Pix / boleto / card. `X-Idempotency-Key` is mandatory
      # (one UUID per Charge attempt, so retries never double-charge).
      def create_payment(body:, idempotency_key:)
        post("/v1/payments", body: body, headers: { "X-Idempotency-Key" => idempotency_key })
      end

      # POST /checkout/preferences — hosted Checkout Pro link (returns init_point).
      def create_preference(body:)
        post("/checkout/preferences", body: body)
      end

      # GET /v1/payments/{id} — the AUTHORITATIVE status read. Webhooks carry only
      # the id; never trust their body for state.
      def get_payment(id)
        get("/v1/payments/#{id}")
      end

      # POST /oauth/token — exchange an authorization code (or refresh token) for a
      # connected-account access token. Authenticates with client_id/secret in the
      # body, not a Bearer header.
      def oauth_token(body:)
        handle(no_auth_connection.post("/oauth/token", body))
      end

      # GET on the MP API with the Bearer token.
      def get(path, params: {})
        handle(connection.get(path, params))
      end

      # POST JSON on the MP API with the Bearer token + optional extra headers.
      def post(path, body:, headers: {})
        handle(connection.post(path) do |req|
          headers.each { |k, v| req.headers[k] = v }
          req.body = body
        end)
      end

      private

      # Bearer-authenticated JSON connection (encode/decode + retry on 429/5xx).
      def connection
        @connection ||= build_connection(BASE, auth_token: access_token)
      end

      # Connection without an Authorization header, for the OAuth token exchange.
      def no_auth_connection
        @no_auth_connection ||= build_connection(BASE)
      end

      # The agency's own connected MP token (multi-tenant), if present.
      def workspace_access_token
        workspace&.setting&.mercadopago_access_token.presence
      end
    end
  end
end
