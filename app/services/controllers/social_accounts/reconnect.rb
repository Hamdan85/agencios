# frozen_string_literal: true

module Controllers
  module SocialAccounts
    # POST /social_accounts/:id/reconnect — STUB. Real OAuth re-auth runs through
    # Operations::Social::ConnectAccount, which re-runs the provider's OAuth flow
    # and refreshes the encrypted tokens.
    class Reconnect < Base
      def initialize(params:)
        @params = params
      end

      def call
        deny_guests!
        account = workspace.social_accounts.find(@params[:id])
        account.update!(status: :connected)
        { social_account: serialize(account, SocialAccountSerializer) }
      end
    end
  end
end
