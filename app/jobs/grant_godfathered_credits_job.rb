# frozen_string_literal: true

# Refills the monthly credit allotment for godfathered workspaces that have a
# `monthly_credit_limit` set. These workspaces don't pay Stripe, so the
# invoice.paid grant path never fires for them — this scheduled sweep stands in,
# resetting their granted bucket at the start of each month.
#
# The refill is also applied lazily on debit/preflight (see
# Operations::Credits::EnsureGodfatheredGrant), so this sweep is just the belt to
# that suspenders — it keeps balances correct even for idle workspaces. Runs
# per-workspace so one failure doesn't abort the whole sweep.
#
# Scheduled via sidekiq-cron (see config/schedule.yml).
class GrantGodfatheredCreditsJob < ApplicationJob
  queue_as :low

  def perform(workspace_id = nil)
    if workspace_id
      refill(Workspace.find_by(id: workspace_id))
    else
      Workspace.where(godfathered: true).where.not(monthly_credit_limit: nil).find_each do |workspace|
        refill(workspace)
      rescue StandardError => e
        Rails.logger.error("[GrantGodfatheredCreditsJob] workspace=#{workspace.id} #{e.class}: #{e.message}")
      end
    end
  end

  private

  def refill(workspace)
    return unless workspace

    Operations::Credits::EnsureGodfatheredGrant.call(workspace: workspace)
  end
end
