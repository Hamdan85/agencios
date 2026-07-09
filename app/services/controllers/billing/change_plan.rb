# frozen_string_literal: true

module Controllers
  module Billing
    # POST /api/v1/billing/change_plan
    #
    # Routes plan changes through Stripe — never flips the local status to active
    # without a real payment (that would be a free-access backdoor).
    #   * No live Stripe subscription yet ⇒ return a Checkout URL (collect card,
    #     start the trial, begin billing).
    #   * Existing subscription ⇒ swap the licensed price in Stripe; the
    #     `customer.subscription.updated` webhook reconciles the local row.
    class ChangePlan < Base
      def initialize(params:)
        @params = params
      end

      def call
        require_owner!
        plan_meta = Plans.find(@params[:plan])
        raise Operations::Errors::Invalid, 'Plano inválido.' unless plan_meta
        raise Operations::Errors::SeatLimitReached, seat_overage_message(plan_meta) if seat_overage?(plan_meta)

        interval = @params[:interval].presence || 'month'
        subscription = workspace.subscription
        if subscription&.stripe_subscription_id.present?
          update_via_stripe(subscription, plan_meta, interval)
        else
          { checkout_url: checkout_url(plan_meta, interval) }
        end
      rescue Vendors::Base::NotConfiguredError
        # Dev/local without Stripe keys — fall back to the mock checkout screen.
        # In production a missing Stripe config is a real outage (the user would
        # otherwise be bounced silently back to /assinatura), so let it crash.
        raise unless Rails.env.local?

        { checkout_url: "#{SystemConfig.app_host}/assinatura?checkout=mock" }
      end

      private

      # Blocks the downgrade outright rather than letting the workspace land in
      # an inconsistent state (fewer seats than active members). The owner must
      # remove members down to the new plan's limit first.
      def seat_overage?(plan_meta) = workspace.memberships.count > plan_meta[:seats].to_i

      def seat_overage_message(plan_meta)
        "O plano #{plan_meta[:name]} permite até #{plan_meta[:seats]} assentos, mas o workspace " \
          "tem #{workspace.memberships.count} membros. Remova membros antes de trocar de plano."
      end

      def update_via_stripe(subscription, plan_meta, interval)
        Vendors::Stripe::Actions::UpdateSubscription.call(
          subscription: subscription,
          plan: plan_meta[:key],
          interval: interval
        )
        # The webhook finalizes; return the current row so the UI can reflect a
        # pending change.
        { subscription: serialize(subscription.reload, SubscriptionSerializer) }
      end

      def checkout_url(plan_meta, interval)
        Vendors::Stripe::Actions::CreateCheckoutSession.call(
          workspace: workspace,
          plan: plan_meta[:key],
          interval: interval,
          success_url: "#{SystemConfig.app_host}/assinatura?checkout=success",
          cancel_url: "#{SystemConfig.app_host}/assinatura?checkout=cancelled"
        ).url
      end
    end
  end
end
