# frozen_string_literal: true

module Controllers
  module PublicConnect
    # Shared helpers for the public, login-less per-client connect page. The
    # signed link token IS the bearer credential (like an invitation token), so
    # the client never needs an agencios account. Networks are connected straight
    # onto the client referenced by the token.
    class Base < Controllers::Base
      SALT = 'agencios:client_connect'

      # Networks offered on the public page when PostGate is off — every network
      # the agency can connect for a client through the direct per-vendor OAuth
      # flow. Each maps to a connect slug via Publishers::SocialPublisher. Kept as
      # a plain constant (rather than folded into .networks) for rollback safety.
      DIRECT_NETWORKS = %w[instagram facebook threads tiktok youtube linkedin x].freeze
      NETWORKS = DIRECT_NETWORKS

      # Networks PostGate connects that have no direct per-vendor OAuth flow —
      # only ever offered once SystemConfig.postgate_enabled?.
      POSTGATE_ONLY_NETWORKS = %w[pinterest bluesky mastodon telegram google_business].freeze

      # The full set of networks offered right now — extended with the
      # PostGate-only networks once the aggregator is live.
      def self.networks
        SystemConfig.postgate_enabled? ? (DIRECT_NETWORKS + POSTGATE_ONLY_NETWORKS) : DIRECT_NETWORKS
      end

      # URL-safe signed token so it can live in the `/conectar/:token` path
      # without `/`, `+`, `=` or `.` (which a default verifier emits and which
      # break route/segment/format parsing). Domain-separated via SALT.
      def self.verifier
        secret = Rails.application.key_generator.generate_key(SALT)
        ActiveSupport::MessageVerifier.new(secret, url_safe: true, serializer: JSON)
      end

      # Generate the long-lived token the agency shares with the client.
      def self.token_for(client)
        verifier.generate({ 'client_id' => client.id }, expires_in: 30.days)
      end

      private

      # Resolve the client from the signed token, or raise Invalid.
      def client_from_token(token)
        data = self.class.verifier.verify(token.to_s)
        Client.find(data['client_id'])
      rescue StandardError
        raise Operations::Errors::Invalid, 'token'
      end
    end
  end
end
