# frozen_string_literal: true

# Runs once at the start of the day (see config/schedule.yml) and sends every
# user with at least one billing-active workspace their ticket digest for
# today. Runs per-user so one failure doesn't abort the whole sweep.
class SendDailyTicketDigestJob < ApplicationJob
  queue_as :low

  def perform
    User.includes(workspaces: :subscription).find_each do |user|
      Operations::Digests::SendDailyTicketDigest.call(user: user)
    rescue StandardError => e
      Rails.logger.error("[SendDailyTicketDigestJob] user=#{user.id} #{e.class}: #{e.message}")
    end
  end
end
