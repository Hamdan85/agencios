# frozen_string_literal: true

module Controllers
  module PublicConnect
    # Shared helpers for the public, login-less per-client connect page. The
    # signed link token IS the bearer credential (like an invitation token), so
    # the client never needs an agencios account. Networks are connected straight
    # onto the client referenced by the token.
    class Base < Controllers::Base
      SALT = "agencios:client_connect"

      # Networks offered on the public page — every network the agency can connect
      # for a client. Each maps to a connect slug via Publishers::SocialPublisher.
      NETWORKS = %w[instagram facebook threads tiktok youtube linkedin x].freeze

      # URL-safe signed token so it can live in the `/conectar/:token` path
      # without `/`, `+`, `=` or `.` (which a default verifier emits and which
      # break route/segment/format parsing). Domain-separated via SALT.
      def self.verifier
        secret = Rails.application.key_generator.generate_key(SALT)
        ActiveSupport::MessageVerifier.new(secret, url_safe: true, serializer: JSON)
      end

      # Generate the long-lived token the agency shares with the client.
      def self.token_for(client)
        verifier.generate({ "client_id" => client.id }, expires_in: 30.days)
      end

      private

      # Resolve the client from the signed token, or raise Invalid.
      def client_from_token(token)
        data = self.class.verifier.verify(token.to_s)
        Client.find(data["client_id"])
      rescue StandardError
        raise Operations::Errors::Invalid, "token"
      end
    end
  end
end
