# frozen_string_literal: true

# Scheduled sweep (sidekiq-cron, see config/schedule.yml) that keeps each billed
# workspace's Stripe seat quantity in sync via Operations::Billing::ReconcileSeats.
# Runs per-workspace so one Stripe error doesn't abort the whole sweep. See
# docs/integrations/stripe-billing.md §5.
class ReconcileSeatsJob < ApplicationJob
  queue_as :low

  # No args ⇒ sweep every billed workspace. With a workspace_id ⇒ reconcile one.
  def perform(workspace_id = nil)
    if workspace_id
      Operations::Billing::ReconcileSeats.call(workspace: Workspace.find_by(id: workspace_id))
    else
      Subscription.where.not(stripe_subscription_id: nil).find_each do |subscription|
        Operations::Billing::ReconcileSeats.call(workspace: subscription.workspace)
      rescue StandardError => e
        Rails.logger.error("[ReconcileSeatsJob] workspace=#{subscription.workspace_id} #{e.class}: #{e.message}")
      end
    end
  end
end
