# frozen_string_literal: true

module Operations
  module Social
    # Data Deletion Request (LGPD/GDPR): a user asked the network to delete the
    # data we hold about them. We destroy their SocialAccount(s) for the
    # provider(s) — the personal data we store is the connection itself (tokens,
    # profile, external ids). Posts reference the account with `dependent:
    # :nullify`, so historical posts are kept but de-linked from the person.
    class DeleteUserData < Operations::Base
      def initialize(providers:, external_user_id:)
        @providers = Array(providers).map(&:to_s)
        @external_user_id = external_user_id.to_s
      end

      def call
        return 0 if @external_user_id.blank? || @providers.empty?

        accounts = SocialAccount.where(provider: @providers, external_user_id: @external_user_id)
        count = 0
        accounts.find_each do |account|
          account.destroy!
          count += 1
        end
        count
      end
    end
  end
end
