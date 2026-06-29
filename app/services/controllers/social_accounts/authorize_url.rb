# frozen_string_literal: true

module Controllers
  module SocialAccounts
    # GET /clients/:client_id/social_accounts/authorize_url?network=instagram —
    # returns the OAuth URL the browser opens to connect the network for this
    # client (signed state carries the client id + network).
    class AuthorizeUrl < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        client = workspace.clients.find(@params[:client_id])
        authorize!(client, :update?)
        network = @params.require(:network).to_s
        slug = Publishers::SocialPublisher.connect_slug(network)
        raise Operations::Errors::Invalid, "Rede não suportada: #{network}" unless slug

        vendor = Publishers::SocialPublisher.vendor_for_slug(slug)
        url = vendor::Actions::AuthorizeUrl.call(
          workspace: client.workspace,
          redirect_uri: "#{SystemConfig.app_host}/auth/#{slug}/callback",
          state: signed_state(client, network)
        )
        { url: url }
      end

      private

      def signed_state(client, network)
        Rails.application.message_verifier("agencios:social_connect")
             .generate({ "client_id" => client.id, "network" => network }, expires_in: 1.hour)
      end
    end
  end
end
