# frozen_string_literal: true

module Controllers
  module SocialAccounts
    class Index < Base
      def call
        accounts = workspace.social_accounts.order(:provider)
        { social_accounts: serialize_collection(accounts, SocialAccountSerializer) }
      end
    end
  end
end
