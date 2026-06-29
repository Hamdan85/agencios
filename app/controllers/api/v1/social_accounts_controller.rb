# frozen_string_literal: true

module Api
  module V1
    # Connected social networks for the active workspace. Removing an account is
    # manager-gated; reconnecting is a member action (enforced in the services).
    class SocialAccountsController < BaseController
      def index   = render_ok(Controllers::SocialAccounts::Index.call)

      # GET /social_accounts/authorize?network=instagram — returns the OAuth URL
      # the browser opens to connect the network (state carries the workspace).
      def authorize_url = render_ok(Controllers::SocialAccounts::AuthorizeUrl.call(params:))

      def destroy   = render_ok(Controllers::SocialAccounts::Destroy.call(params:))

      # POST /social_accounts/:id/reconnect — STUB (see the service).
      def reconnect = render_ok(Controllers::SocialAccounts::Reconnect.call(params:))
    end
  end
end
