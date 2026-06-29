# frozen_string_literal: true

module Operations
  module Social
    # Persists (or updates) a SocialAccount from the attrs a vendor's
    # ConnectAccount action returns after the OAuth code exchange.
    class ConnectAccount < Operations::Base
      def initialize(workspace:, attrs:)
        @workspace = workspace
        @attrs = attrs.symbolize_keys
      end

      def call
        provider = @attrs.fetch(:provider)
        account = @workspace.social_accounts.find_or_initialize_by(provider: provider)
        account.assign_attributes(
          @attrs.except(:provider).merge(status: :connected, last_synced_at: Time.current)
        )
        account.save!
        account
      end
    end
  end
end
