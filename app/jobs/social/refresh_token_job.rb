# frozen_string_literal: true

module Social
  # Per-provider token refresh. With no provider, sweeps every account expiring
  # soon. Scheduled per provider via sidekiq-cron.
  class RefreshTokenJob < ApplicationJob
    queue_as :low

    def perform(provider = nil)
      scope = SocialAccount.status_connected.where.not(token_expires_at: nil)
                           .where(token_expires_at: ..3.days.from_now)
      scope = scope.where(provider: provider) if provider

      scope.find_each do |account|
        Operations::Social::RefreshToken.call(social_account: account)
      rescue StandardError => e
        Rails.logger.warn("[Social::RefreshTokenJob] account ##{account.id}: #{e.message}")
      end
    end
  end
end
