# frozen_string_literal: true

# The agency's own SaaS plan (billed to the workspace via Stripe).
#
# There is NO free tier: access requires an active paid plan, or a trial with a
# credit card on file. A trialing subscription without a card grants no access —
# the workspace sits behind the paywall until checkout collects a card.
class Subscription < ApplicationRecord
  belongs_to :workspace

  enum :plan, { solo: 0, agencia: 1, enterprise: 2 }

  ACTIVE_STATUSES = %w[active trialing past_due].freeze

  # Whether the subscription currently grants app access.
  #   * active / past_due       → yes (past_due keeps access while dunning runs)
  #   * trialing                → only if a card is on file AND the trial window
  #                               is still open (card-required trial)
  #   * anything else           → no
  def access_granted?
    return true if %w[active past_due].include?(status)
    return card_on_file? && trial_active? if trialing?

    false
  end

  def trialing? = status == "trialing"

  def trial_active?
    trial_ends_at.blank? || trial_ends_at.future?
  end

  def seat_limit = Pricing.seat_limit_for(plan)

  # BRL cents the plan lists at (for display / Stripe fallback).
  def price_cents = Pricing.plan(plan)&.fetch(:price_cents, 0) || 0

  def self.ransackable_attributes(_auth = nil)
    %w[id workspace_id plan status seats card_on_file stripe_customer_id
       stripe_subscription_id trial_ends_at current_period_end cancel_at created_at updated_at]
  end

  def self.ransackable_associations(_auth = nil)
    %w[workspace]
  end
end
