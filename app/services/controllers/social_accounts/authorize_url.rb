# frozen_string_literal: true

module Controllers
  module SocialAccounts
    # GET /clients/:client_id/social_accounts/authorize_url?network=instagram —
    # returns the OAuth URL the browser opens to connect the network for this
    # client (signed state carries the client id + network).
    #
    # When PostGate is live (SystemConfig.postgate_enabled?), every network's
    # connect URL is requested through the PostGate hosted-connect flow instead
    # of the direct per-vendor OAuth dialog — the direct branch below is kept
    # fully intact (untouched, rollback-safe) for when the flag is off, at which
    # point a PostGate-only network (pinterest/bluesky/mastodon/telegram/
    # google_business) still raises the same unsupported-network error as today
    # (Publishers::SocialPublisher has no CONNECT_SLUG entry for them).
    class AuthorizeUrl < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        client = workspace.clients.find(@params[:client_id])
        authorize!(client, :update?)
        network = @params.require(:network).to_s

        return postgate_connect_url(client, network) if SystemConfig.postgate_enabled?

        slug = Publishers::SocialPublisher.connect_slug(network)
        raise Operations::Errors::Invalid, I18n.t('api.social.unsupported_network', network: network) unless slug

        vendor = Publishers::SocialPublisher.vendor_for_slug(slug)
        url = vendor::Actions::AuthorizeUrl.call(
          workspace: client.workspace,
          redirect_uri: "#{SystemConfig.app_host}/auth/#{slug}/callback",
          state: signed_state(client, network)
        )
        { url: url }
      end

      private

      # `instance_url` is only meaningful for Mastodon (the instance the account
      # lives on) — dropped for every other network even if the client sent one.
      def postgate_connect_url(client, network)
        Operations::Social::Postgate::CreateConnectUrl.call(
          client: client, network: network, state: signed_state(client, network),
          instance_url: network == 'mastodon' ? @params[:instance_url].presence : nil
        )
      end

      def signed_state(client, network)
        Rails.application.message_verifier('agencios:social_connect')
             .generate({ 'client_id' => client.id, 'network' => network }, expires_in: 1.hour)
      end
    end
  end
end
