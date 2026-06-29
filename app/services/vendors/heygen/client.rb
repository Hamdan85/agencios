# frozen_string_literal: true

module Vendors
  module Heygen
    # Low-level HeyGen API wrapper (developers.heygen.com).
    #
    # Auth: every request carries the `X-Api-Key` header (NOT a Bearer token).
    # Base URL: https://api.heygen.com. Two API generations coexist — classic v2
    # (`/v2/video/generate`, `video_inputs`) supported through Oct 31 2026, and v3
    # (`/v3/videos`, `aspect_ratio` + `script`) for new builds. This client
    # exposes both paths via plain `get`/`post`; the Actions choose the version.
    #
    # The app-level API key comes from credentials (`heygen.api_key`) with an
    # ENV fallback (`HEYGEN_API_KEY`). See docs/integrations/heygen.md.
    class Client < Vendors::Base
      BASE_URL = "https://api.heygen.com"

      def initialize(api_key: nil)
        @api_key = api_key || credential(:heygen, :api_key, env: "HEYGEN_API_KEY")
      end

      def get(path, params = {})
        require_credential!(@api_key, "heygen.api_key")
        handle(connection.get(path, params))
      end

      def post(path, body = {})
        require_credential!(@api_key, "heygen.api_key")
        handle(connection.post(path, body))
      end

      def patch(path, body = {})
        require_credential!(@api_key, "heygen.api_key")
        handle(connection.patch(path, body))
      end

      def delete(path)
        require_credential!(@api_key, "heygen.api_key")
        handle(connection.delete(path))
      end

      private

      def connection
        @connection ||= build_connection(
          BASE_URL,
          headers: {
            "X-Api-Key" => @api_key.to_s,
            "Accept" => "application/json"
          }
        )
      end

      # HeyGen envelopes errors two ways: legacy v2 uses a top-level `error`
      # (string or null), v3 uses a structured `{ error: { code, message } }`.
      # `Vendors::Base#handle` already maps non-2xx HTTP into typed errors; here
      # we additionally raise on a 200 body that still carries an `error`.
      def handle(response)
        body = super(response)
        if body.is_a?(Hash) && body["error"].present?
          raise Vendors::Heygen::Error.from_body(body["error"], status: response.status, body: body)
        end
        body
      end
    end
  end
end
