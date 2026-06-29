# frozen_string_literal: true

module Controllers
  module SocialAccounts
    # Connected networks for one client (nested under /clients/:client_id).
    class Index < Base
      def initialize(params:)
        @params = params
      end

      def call
        client = workspace.clients.find(@params[:client_id])
        authorize!(client, :show?)
        accounts = client.social_accounts.order(:provider)
        { social_accounts: serialize_collection(accounts, SocialAccountSerializer) }
      end
    end
  end
end
