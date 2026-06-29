# frozen_string_literal: true

module Controllers
  module SocialAccounts
    # GET /social_accounts/authorize?network=instagram — returns the OAuth URL the
    # browser opens to connect the network (signed state carries the workspace).
    class AuthorizeUrl < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        network = @params.require(:network).to_s
        slug = Publishers::SocialPublisher.connect_slug(network)
        raise Operations::Errors::Invalid, "Rede não suportada: #{network}" unless slug

        vendor = Publishers::SocialPublisher.vendor_for_slug(slug)
        url = vendor::Actions::AuthorizeUrl.call(
          workspace: workspace,
          redirect_uri: "#{SystemConfig.app_host}/auth/#{slug}/callback",
          state: signed_state(network)
        )
        { url: url }
      end

      private

      def signed_state(network)
        Rails.application.message_verifier("agencios:social_connect")
             .generate({ "workspace_id" => workspace.id, "network" => network }, expires_in: 1.hour)
      end
    end
  end
end
