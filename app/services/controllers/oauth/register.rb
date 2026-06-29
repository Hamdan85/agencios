# frozen_string_literal: true

module Controllers
  module Oauth
    # RFC 7591 Dynamic Client Registration. Creates the Doorkeeper application a
    # client (Claude) will use for the authorization-code + PKCE flow. This is
    # the one place allowed to create a Doorkeeper::Application directly — it is
    # that entity's own creator service.
    class Register < Controllers::Base
      ALLOWED_SCOPES = %w[read write billing].freeze
      DEFAULT_SCOPES = "read write"

      def initialize(params:)
        @params = params
      end

      def call
        metadata = permitted_metadata
        uris = Array(metadata[:redirect_uris]).reject(&:blank?)
        raise Operations::Errors::Invalid, "redirect_uris is required" if uris.empty?

        validate_redirect_uris!(uris)
        public_client = metadata[:token_endpoint_auth_method].to_s == "none"

        application = ::Doorkeeper::Application.new(
          name: metadata[:client_name].presence || "MCP Client",
          redirect_uri: uris.join("\n"),
          scopes: requested_scopes(metadata[:scope]),
          confidential: !public_client,
          dynamically_registered: true,
          registration_access_token: SecureRandom.urlsafe_base64(32)
        )
        application.save!

        registration_response(application, uris, public_client)
      end

      private

      def permitted_metadata
        @params.permit(
          :client_name, :token_endpoint_auth_method, :scope,
          redirect_uris: [], grant_types: [], response_types: [], contacts: []
        )
      end

      # https only (localhost allowed for local development / MCP Inspector).
      def validate_redirect_uris!(uris)
        uris.each do |uri|
          parsed = URI.parse(uri)
          ok = parsed.is_a?(URI::HTTPS) || %w[localhost 127.0.0.1].include?(parsed.host)
          raise Operations::Errors::Invalid, "redirect_uri must use https: #{uri}" unless ok
        rescue URI::InvalidURIError
          raise Operations::Errors::Invalid, "invalid redirect_uri: #{uri}"
        end
      end

      def requested_scopes(scope)
        wanted = scope.to_s.split & ALLOWED_SCOPES
        wanted.presence&.join(" ") || DEFAULT_SCOPES
      end

      def registration_response(application, uris, public_client)
        body = {
          client_id: application.uid,
          client_id_issued_at: application.created_at.to_i,
          client_name: application.name,
          redirect_uris: uris,
          grant_types: %w[authorization_code refresh_token],
          response_types: %w[code],
          token_endpoint_auth_method: public_client ? "none" : "client_secret_basic",
          scope: application.scopes.to_s
        }
        unless public_client
          body[:client_secret] = application.plaintext_secret
          body[:client_secret_expires_at] = 0 # never expires
        end
        body
      end
    end
  end
end
