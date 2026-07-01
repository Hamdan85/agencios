# frozen_string_literal: true

module Controllers
  module PublicConnect
    # Build the OAuth authorize URL for a network from the public page. The signed
    # OAuth state carries the client id + network + the link token, so the shared
    # callback persists onto the right client AND can return the popup/mobile flow
    # back to this public page (not the agency app).
    class Authorize < Base
      def initialize(token:, network:)
        @token = token
        @network = network.to_s
      end

      def call
        client = client_from_token(@token)
        raise Operations::Errors::Invalid, 'network' unless NETWORKS.include?(@network)

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

      def signed_state(client)
        Rails.application.message_verifier('agencios:social_connect').generate(
          { 'client_id' => client.id, 'network' => @network, 'link' => @token },
          expires_in: 1.hour
        )
      end
    end
  end
end
