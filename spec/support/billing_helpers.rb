# frozen_string_literal: true

# There is no free tier: a freshly-registered workspace starts in the
# `incomplete` state (no access) and the total paywall
# (`Api::V1::BaseController#require_active_billing`) returns 402 for every
# endpoint. Request specs that exercise the app past the paywall must first put
# the workspace into a billing-active state.
module BillingSpecHelpers
  # Simulate a paid, card-on-file subscription (post-checkout state).
  def activate_billing(workspace)
    sub = workspace.subscription || workspace.build_subscription(plan: :solo, seats: 1)
    sub.update!(status: 'active', card_on_file: true, current_period_end: 30.days.from_now)
    workspace
  end

  # Give the workspace spendable prepaid credits (for generation specs).
  def credit_workspace(workspace, amount)
    Operations::Credits::Purchase.call(
      workspace: workspace, amount: amount, reference: "spec-#{SecureRandom.hex(4)}"
    )
  end
end

RSpec.configure { |config| config.include BillingSpecHelpers }
