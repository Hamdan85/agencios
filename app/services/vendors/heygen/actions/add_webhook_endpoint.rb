# frozen_string_literal: true

module Vendors
  module Heygen
    module Actions
      # Register a webhook endpoint so HeyGen calls us back on render completion.
      #
      # v3 (default): `POST /v3/webhooks/endpoints` with `{ url, events, entity_id? }`.
      # v1 (legacy):  `POST /v1/webhook/endpoint.add` with `{ url, events }`.
      #
      # The response includes `endpoint_id`, `url`, `events`, `status`, and a
      # `secret` (returned ONLY on create / rotate-secret — store it in
      # credentials as `heygen.webhook_secret` for signature verification).
      #
      # Run once (rake task / installer) pointing at the agencios webhook URL.
      # Returns the parsed endpoint object (incl. `secret`).
      #
      # See docs/integrations/heygen.md §3e.
      class AddWebhookEndpoint
        def self.call(...) = new(...).call

        DEFAULT_EVENTS = %w[avatar_video.success avatar_video.fail].freeze

        def initialize(url:, events: DEFAULT_EVENTS, version: :v3, entity_id: nil, client: nil)
          @url       = url
          @events    = events
          @version   = version.to_sym
          @entity_id = entity_id
          @client    = client || Client.new
        end

        def call
          body = @version == :v1 ? add_v1 : add_v3
          body['data'] || body
        end

        private

        def add_v3
          payload = { url: @url, events: @events }
          payload[:entity_id] = @entity_id if @entity_id
          @client.post('/v3/webhooks/endpoints', payload)
        end

        def add_v1
          @client.post('/v1/webhook/endpoint.add', { url: @url, events: @events })
        end
      end
    end
  end
end
