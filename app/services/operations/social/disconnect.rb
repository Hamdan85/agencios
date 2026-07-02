# frozen_string_literal: true

module Operations
  module Social
    # The agency manually disconnects one client's connected network. We do NOT
    # delete the row: posts published through it must keep their history/metrics
    # (and posts.social_account_id is NOT NULL). Instead we soft-revoke and drop
    # the stored tokens. Because ConnectAccount reuses the same (client, provider)
    # row via find_or_initialize_by, reconnecting later revives THIS record and
    # every past post stays linked automatically.
    class Disconnect < Operations::Base
      def initialize(account:)
        @account = account
      end

      def call
        @account.update!(
          status: :revoked,
          revoked_at: Time.current,
          user_access_token: nil,
          page_access_token: nil,
          refresh_token: nil,
          token_expires_at: nil,
          refresh_token_expires_at: nil
        )
        @account
      end
    end
  end
end
