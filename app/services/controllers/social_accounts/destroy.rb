# frozen_string_literal: true

module Controllers
  module SocialAccounts
    class Destroy < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_manager!
        client = workspace.clients.find(@params[:client_id])
        account = client.social_accounts.find(@params[:id])
        Operations::Social::Disconnect.call(account: account)
        { message: I18n.t('api.social.disconnected') }
      end
    end
  end
end
