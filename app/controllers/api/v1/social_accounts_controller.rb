# frozen_string_literal: true

module Api
  module V1
    # A client's connected social networks (nested under /clients/:client_id).
    # Removing an account is manager-gated; reconnecting is a member action
    # (enforced in the services).
    class SocialAccountsController < BaseController
      def index = render_ok(Controllers::SocialAccounts::Index.call(params:))

      # GET /clients/:client_id/social_accounts/authorize_url?network=instagram —
      # returns the OAuth URL the browser opens (state carries the client).
      def authorize_url = render_ok(Controllers::SocialAccounts::AuthorizeUrl.call(params:))

      # GET /clients/:client_id/social_accounts/connect_link — shareable login-less
      # link the client opens to connect their own networks.
      def connect_link = render_ok(Controllers::SocialAccounts::ConnectLink.call(params:))

      def destroy   = render_ok(Controllers::SocialAccounts::Destroy.call(params:))

      # POST /clients/:client_id/social_accounts/:id/reconnect — STUB (see the service).
      def reconnect = render_ok(Controllers::SocialAccounts::Reconnect.call(params:))
    end
  end
end
