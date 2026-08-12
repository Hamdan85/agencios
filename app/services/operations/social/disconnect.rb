# frozen_string_literal: true

module Operations
  module Social
    # The agency manually disconnects one client's connected network. We do NOT
    # delete the row: posts published through it must keep their history/metrics
    # (and posts.social_account_id is NOT NULL). Instead we soft-revoke and drop
    # the stored tokens. Because ConnectAccount reuses the same (client, provider)
    # row via find_or_initialize_by, reconnecting later revives THIS record and
    # every past post stays linked automatically.
    #
    # A postgate-sourced account also best-effort deletes the remote Profile
    # (`remote: true`, the default) — pass `remote: false` when the profile is
    # already gone on PostGate's side (e.g. the `profile.disconnected` webhook,
    # which fires AFTER the remote deletion already happened) to skip the
    # redundant API call.
    class Disconnect < Operations::Base
      def initialize(account:, remote: true)
        @account = account
        @remote = remote
      end

      def call
        delete_remote_profile if @remote
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

      private

      def delete_remote_profile
        return unless @account.connection_source_postgate? && @account.postgate_profile_id.present?

        Vendors::Postgate::Client.new.delete_profile(@account.postgate_profile_id)
      rescue Vendors::Base::Error => e
        Rails.logger.warn(
          "[Social::Disconnect] postgate delete_profile failed for account ##{@account.id}: #{e.message}"
        )
      end
    end
  end
end
