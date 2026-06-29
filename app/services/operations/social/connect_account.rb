# frozen_string_literal: true

module Operations
  module Social
    # Persists (or updates) a SocialAccount, owned by the CLIENT, from the attrs a
    # vendor's ConnectAccount action returns after the OAuth code exchange. The
    # workspace is derived from the client and kept for tenant scoping.
    class ConnectAccount < Operations::Base
      def initialize(client:, attrs:)
        @client = client
        @attrs = attrs.symbolize_keys
      end

      def call
        provider = @attrs.fetch(:provider)
        account = @client.social_accounts.find_or_initialize_by(provider: provider)
        account.workspace = @client.workspace
        account.assign_attributes(
          @attrs.except(:provider).merge(status: :connected, last_synced_at: Time.current)
        )
        account.save!
        account
      end
    end
  end
end
