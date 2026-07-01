# frozen_string_literal: true

# Keeps each workspace's Stripe licensed (seat) item quantity in sync with its
# actual `seat_count` (= membership count). Memberships are added/removed in the
# app without touching Stripe; this scheduled sweep pushes the true seat count to
# the subscription's licensed item, so the next invoice bills the right number of
# seats (Stripe prorates licensed-quantity changes automatically).
#
# Metered usage items are ignored — only the licensed plan/seat item carries a
# quantity. Runs per-workspace so one Stripe error doesn't abort the whole sweep.
#
# Scheduled via sidekiq-cron (see config/sidekiq.yml). See
# docs/integrations/stripe-billing.md §5.
class ReconcileSeatsJob < ApplicationJob
  queue_as :low

  # No args ⇒ sweep every billed workspace. With a workspace_id ⇒ reconcile one.
  def perform(workspace_id = nil)
    if workspace_id
      reconcile(Workspace.find_by(id: workspace_id))
    else
      Subscription.where.not(stripe_subscription_id: nil).find_each do |subscription|
        reconcile(subscription.workspace)
      rescue StandardError => e
        Rails.logger.error("[ReconcileSeatsJob] workspace=#{subscription.workspace_id} #{e.class}: #{e.message}")
      end
    end
  end

  private

  def reconcile(workspace)
    return unless workspace

    subscription = workspace.subscription
    return if subscription&.stripe_subscription_id.blank?

    client = Vendors::Stripe::Client.new
    stripe_sub = client.retrieve_subscription(
      subscription.stripe_subscription_id, expand: ['items.data.price']
    )

    item = licensed_item(stripe_sub, client)
    return unless item

    desired = workspace.seat_count
    return if desired <= 0
    return if item.quantity == desired

    client.update_subscription_item(item.id, quantity: desired, proration_behavior: 'create_prorations')
    subscription.update!(seats: desired)
  end

  # The licensed seat item is the one whose price id maps to a plan in the
  # credential lookup (metered items don't).
  def licensed_item(stripe_sub, client)
    price_to_plan = plan_price_ids(client)
    stripe_sub.items.data.find { |i| price_to_plan.include?(i.price&.id) }
  end

  def plan_price_ids(client)
    Vendors::Stripe::Client::PLAN_PRICE_KEYS.keys.filter_map do |plan|
      client.plan_price_id(plan)
    rescue Vendors::Base::NotConfiguredError
      nil
    end
  end
end
