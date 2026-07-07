# frozen_string_literal: true

module Operations
  module Billing
    # Pushes a workspace's true seat count (= membership count) to its Stripe
    # licensed item and mirrors it on the local Subscription row. Memberships are
    # added/removed in the app without touching Stripe; the scheduled
    # ReconcileSeatsJob sweep calls this per workspace so the next invoice bills
    # the right number of seats.
    class ReconcileSeats < Operations::Base
      def initialize(workspace:)
        @workspace = workspace
      end

      def call
        return unless @workspace

        subscription = @workspace.subscription
        return if subscription&.stripe_subscription_id.blank?

        desired = @workspace.seat_count
        return if desired <= 0

        updated = Vendors::Stripe::Actions::SyncSeatQuantity.call(
          subscription: subscription, quantity: desired
        )
        subscription.update!(seats: desired) if updated
      end
    end
  end
end
