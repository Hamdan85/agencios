# frozen_string_literal: true

module Operations
  module Social
    # A client removed our app from their network account (Meta/Instagram/Threads
    # deauthorize callback). Mark every matching connected account as `revoked` so
    # the agency sees it needs reconnecting and we stop trying to publish with a
    # dead token. Matches on the app-scoped external user id within the provider.
    #
    # The same person may have connected several clients with one login, so this
    # revokes ALL of that user's accounts for the given provider(s).
    class Deauthorize < Operations::Base
      def initialize(providers:, external_user_id:)
        @providers = Array(providers).map(&:to_s)
        @external_user_id = external_user_id.to_s
      end

      def call
        return 0 if @external_user_id.blank? || @providers.empty?

        accounts = SocialAccount
                   .where(provider: @providers, external_user_id: @external_user_id)
                   .where.not(status: :revoked)

        count = 0
        accounts.find_each do |account|
          account.update!(status: :revoked, revoked_at: Time.current)
          count += 1
        end
        count
      end
    end
  end
end
