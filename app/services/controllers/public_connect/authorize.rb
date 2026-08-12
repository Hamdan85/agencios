# frozen_string_literal: true

module Controllers
  module PublicConnect
    # Build the OAuth authorize URL for a network from the public page. The signed
    # OAuth state carries the client id + network + the link token, so the shared
    # callback persists onto the right client AND can return the popup/mobile flow
    # back to this public page (not the agency app).
    #
    # When PostGate is live, every network routes through the PostGate hosted-
    # connect flow instead (see AuthorizeUrl for the same split) — this is what
    # lets the public page offer the PostGate-only networks at all, since they
    # have no direct per-vendor OAuth flow to fall back to.
    class Authorize < Base
      def initialize(token:, network:, instance_url: nil)
        @token = token
        @network = network.to_s
        @instance_url = instance_url
      end

      def call
        client = client_from_token(@token)
        raise Operations::Errors::Invalid, 'network' unless self.class.networks.include?(@network)

        return postgate_connect_url(client) if SystemConfig.postgate_enabled?

        slug = Publishers::SocialPublisher.connect_slug(@network)
        vendor = Publishers::SocialPublisher.vendor_for_slug(slug)
        url = vendor::Actions::AuthorizeUrl.call(
          workspace: client.workspace,
          redirect_uri: "#{SystemConfig.app_host}/auth/#{slug}/callback",
          state: signed_state(client)
        )
        { url: url }
      end

      private

      def postgate_connect_url(client)
        Operations::Social::Postgate::CreateConnectUrl.call(
          client: client, network: @network, state: signed_state(client),
          instance_url: @network == 'mastodon' ? @instance_url.presence : nil
        )
      end

      def signed_state(client)
        Rails.application.message_verifier('agencios:social_connect').generate(
          { 'client_id' => client.id, 'network' => @network, 'link' => @token },
          expires_in: 1.hour
        )
      end
    end
  end
end
