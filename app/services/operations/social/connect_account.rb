# frozen_string_literal: true

module Operations
  module Social
    # Persists (or updates) a SocialAccount, owned by the CLIENT, from the attrs a
    # vendor's ConnectAccount action returns after the OAuth code exchange. The
    # workspace is derived from the client and kept for tenant scoping.
    #
    # Accounts are keyed by the network-side STABLE IDENTITY (not just provider),
    # so a client can alternate between two accounts on the same network without
    # mixing history: each real account is its own row, and its posts stay pinned
    # to it forever. Reconnecting a previously-disconnected account revives ITS
    # row (status → connected), and any OTHER account still active on that network
    # is soft-revoked — only one account per (client, network) is ever connected
    # at a time (alternate, not simultaneous).
    class ConnectAccount < Operations::Base
      # The column that identifies the specific network account. For Meta,
      # external_user_id is the logged-in Facebook USER (shared across their
      # Pages/IG accounts), so the account itself is keyed by page_id / ig_user_id.
      IDENTITY_COLUMN = {
        'facebook' => :page_id,
        'instagram' => :ig_user_id,
        'youtube' => :channel_id
      }.freeze

      def initialize(client:, attrs:)
        @client = client
        @attrs = attrs.symbolize_keys
      end

      def call
        provider = @attrs.fetch(:provider).to_s
        account = @client.social_accounts.find_or_initialize_by(identity_scope(provider))
        account.workspace = @client.workspace
        account.assign_attributes(
          @attrs.except(:provider).merge(status: :connected, last_synced_at: Time.current)
        )
        account.save!
        revoke_others!(provider, account)
        account
      end

      private

      # provider + the stable identity column, so distinct network accounts map to
      # distinct rows. Falls back to external_user_id when the specific id is blank.
      def identity_scope(provider)
        column = IDENTITY_COLUMN[provider] || :external_user_id
        value = @attrs[column].presence || @attrs[:external_user_id]
        { provider: provider, column => value }
      end

      # Enforce a single active account per (client, network): any other
      # non-revoked account on the same network is soft-disconnected.
      def revoke_others!(provider, account)
        @client.social_accounts
               .where(provider: provider)
               .where.not(id: account.id)
               .where.not(status: :revoked)
               .find_each { |other| Operations::Social::Disconnect.call(account: other) }
      end
    end
  end
end
