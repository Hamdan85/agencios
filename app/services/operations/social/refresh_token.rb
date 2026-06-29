# frozen_string_literal: true

module Operations
  module Social
    # Re-exchanges a SocialAccount's token before expiry via the network vendor.
    # On failure, flags the account `needs_reauth` (never silently revokes).
    class RefreshToken < Operations::Base
      def initialize(social_account:)
        @account = social_account
      end

      def call
        vendor = Publishers::SocialPublisher.vendor_for(@account.provider)
        attrs = vendor::Actions::RefreshToken.call(@account) || {}
        @account.update!(attrs.to_h.symbolize_keys.merge(status: :connected))
        @account
      rescue StandardError => e
        @account.update!(status: :needs_reauth)
        Rails.logger.warn("[Social::RefreshToken] #{@account.provider} ##{@account.id}: #{e.message}")
        @account
      end
    end
  end
end
