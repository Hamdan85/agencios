# frozen_string_literal: true

module Social
  # Snapshots profile-level analytics for connected accounts. Runs daily so the
  # account-metric history (and the period deltas a report needs) accrues over
  # time. With a social_account_id, snapshots just that account.
  class SyncAccountInsightsJob < ApplicationJob
    queue_as :media

    def perform(social_account_id = nil)
      if social_account_id
        account = SocialAccount.find_by(id: social_account_id)
        Operations::Social::SyncAccountInsights.call(social_account: account) if account
        return
      end

      SocialAccount.status_connected
                   .where(provider: Operations::Social::SyncAccountInsights::ACTIONS.keys)
                   .find_each do |account|
        Operations::Social::SyncAccountInsights.call(social_account: account)
      rescue StandardError => e
        Rails.logger.warn("[Social::SyncAccountInsightsJob] account ##{account.id}: #{e.message}")
      end
    end
  end
end
