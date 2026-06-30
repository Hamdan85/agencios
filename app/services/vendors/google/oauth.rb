# frozen_string_literal: true

require "openssl"

module Vendors
  module Google
    # Google OAuth 2.0 for "Sign in / Sign up with Google" — the consent URL,
    # the authorization-code exchange, and the OpenID Connect userinfo lookup.
    # Uses the shared Google OAuth client (`credentials.google.*`, ENV fallback
    # GOOGLE_CLIENT_ID/SECRET) — the same client that backs Calendar and YouTube.
    # Raw HTTP only; no DB writes, no domain logic.
    #
    # Hosts:
    #   AUTH     = https://accounts.google.com          (browser consent URL)
    #   TOKEN    = https://oauth2.googleapis.com         (code → tokens)
    #   USERINFO = https://openidconnect.googleapis.com  (profile lookup)
    class Oauth < Vendors::Base
      AUTH     = "https://accounts.google.com"
      TOKEN    = "https://oauth2.googleapis.com"
      USERINFO = "https://openidconnect.googleapis.com"

      # Minimal sign-in scopes: identity + verified email. No offline/Calendar.
      SCOPES = %w[openid email profile].freeze

      # Consent URL. `prompt=select_account` lets a user pick which Google account
      # to use; `access_type=online` since sign-in needs no refresh token.
      def authorize_url(redirect_uri:, state:)
        params = {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: SCOPES.join(" "),
          access_type: "online",
          include_granted_scopes: "true",
          prompt: "select_account",
          state: state
        }
        "#{AUTH}/o/oauth2/v2/auth?#{params.to_query}"
      end

      # POST oauth2.googleapis.com/token (grant_type=authorization_code).
      # Returns { access_token:, expires_in:, scope:, token_type:, id_token: }.
      def exchange_code(code:, redirect_uri:)
        token_post(
          code: code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code"
        )
      end

      # GET /v1/userinfo with the bearer access token. Returns the OIDC profile:
      #   { "sub" =>, "email" =>, "email_verified" =>, "name" =>, "picture" => }
      def fetch_userinfo(access_token:)
        conn = build_connection(USERINFO, auth_token: access_token)
        handle(conn.get("/v1/userinfo"))
      end

      private

      def client_id
        require_credential!(credential(:google, :client_id, env: "GOOGLE_CLIENT_ID"), "google.client_id")
      end

      def client_secret
        require_credential!(credential(:google, :client_secret, env: "GOOGLE_CLIENT_SECRET"), "google.client_secret")
      end

      # Google's token endpoint is form-encoded and returns a flat JSON error
      # (e.g. invalid_grant when the code is reused/expired → restart the flow).
      def token_post(body)
        conn = Faraday.new(url: TOKEN) do |f|
          f.request :url_encoded
          f.response :json, content_type: /\bjson/
          f.request :retry,
                    max: 2, interval: 0.4, backoff_factor: 2,
                    retry_statuses: Vendors::Base::RETRY_STATUSES,
                    methods: %i[post]
          f.adapter Faraday.default_adapter
        end
        response = conn.post("/token", body)
        return response.body if response.success?

        parsed = response.body
        klass = invalid_grant?(parsed) ? AuthenticationError : Error
        raise klass.new(token_error_message(parsed), status: response.status, body: parsed)
      end

      def invalid_grant?(body)
        body.is_a?(Hash) && body["error"] == "invalid_grant"
      end

      def token_error_message(body)
        return "#{body["error"]}: #{body["error_description"]}" if body.is_a?(Hash) && body["error"]

        "OAuth token request failed"
      end
    end
  end
end
