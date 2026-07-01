# frozen_string_literal: true

module Vendors
  # Shared base for all third-party API clients. Wraps Faraday with JSON
  # encoding/decoding, retry on transient failures, and uniform error mapping.
  # App-level secrets come from Rails encrypted credentials (with ENV fallback
  # for local dev); per-workspace tokens come from the model passed in.
  class Base
    class Error < StandardError
      attr_reader :status, :body

      def initialize(message = nil, status: nil, body: nil)
        @status = status
        @body = body
        super(message || "#{self.class.name} (HTTP #{status})")
      end
    end

    class AuthenticationError < Error; end
    class RateLimitError     < Error; end
    class ServerError        < Error; end
    class NotConfiguredError < Error; end

    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

    private

    def build_connection(base_url, headers: {}, auth_token: nil)
      headers = headers.dup
      headers['Authorization'] ||= "Bearer #{auth_token}" if auth_token

      Faraday.new(url: base_url) do |f|
        f.request :json
        f.response :json, content_type: /\bjson/
        f.request :retry,
                  max: 2, interval: 0.4, backoff_factor: 2,
                  retry_statuses: RETRY_STATUSES,
                  methods: %i[get post put delete patch]
        f.headers.merge!(headers)
        f.options.timeout = 30
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end
    end

    # Returns the parsed body on success; raises a mapped error otherwise.
    def handle(response)
      return response.body if response.success?

      klass =
        case response.status
        when 401, 403 then AuthenticationError
        when 429      then RateLimitError
        when 500..599 then ServerError
        else Error
        end
      raise klass.new(error_message(response), status: response.status, body: response.body)
    end

    def error_message(response)
      body = response.body
      return body['error']['message'] if body.is_a?(Hash) && body['error'].is_a?(Hash)
      return body['error'] if body.is_a?(Hash) && body['error'].is_a?(String)
      return body['message'] if body.is_a?(Hash) && body['message']

      "HTTP #{response.status}"
    end

    # App-level secret from credentials, falling back to ENV in local dev.
    def credential(*path, env: nil)
      value = Rails.application.credentials.dig(*path)
      value ||= ENV[env] if env
      value
    end

    def require_credential!(value, name)
      return value if value.present?

      raise NotConfiguredError, "Credencial ausente: #{name}. Configure em rails credentials:edit."
    end
  end
end
