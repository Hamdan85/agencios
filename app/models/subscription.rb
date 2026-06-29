# frozen_string_literal: true

# The agency's own SaaS plan (billed to the workspace via Stripe).
class Subscription < ApplicationRecord
  belongs_to :workspace

  enum :plan, { solo: 0, agencia: 1, enterprise: 2 }

  SEAT_LIMITS = { "solo" => 1, "agencia" => 20, "enterprise" => 1_000_000 }.freeze
  ACTIVE_STATUSES = %w[active trialing past_due].freeze

  def access_granted?
    return true if trialing? && trial_ends_at&.future?

    ACTIVE_STATUSES.include?(status)
  end

  def trialing? = status == "trialing"
  def seat_limit = SEAT_LIMITS.fetch(plan, 1)
end
