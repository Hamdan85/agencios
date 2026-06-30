# frozen_string_literal: true

module Controllers
  module SocialAccounts
    # GET /clients/:client_id/social_accounts/connect_link — the agency gets a
    # shareable, login-less link the client opens on their phone to connect their
    # own networks (Instagram/Facebook). The signed token carries the client id.
    class ConnectLink < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        client = workspace.clients.find(@params[:client_id])
        authorize!(client, :update?)

        token = Controllers::PublicConnect::Base.token_for(client)
        { url: "#{SystemConfig.app_host}/conectar/#{token}", token: token }
      end
    end
  end
end
