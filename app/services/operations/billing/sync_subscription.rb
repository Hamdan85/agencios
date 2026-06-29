# frozen_string_literal: true

module Operations
  module Billing
    # Reconcile a Stripe webhook event into the workspace's local Subscription row.
    #
    # The webhook controller verifies the signature (Vendors::Stripe::Webhook) and
    # hands the parsed Stripe::Event here. We upsert the Subscription
    # (plan, status, seats, stripe_customer_id, stripe_subscription_id,
    # current_period_end, cancel_at) from the event's subscription object, mapping
    # the licensed price id back to a plan via the client's price→plan lookup.
    #
    # Handled events (see docs/integrations/stripe-billing.md §5):
    #   checkout.session.completed                — fetch the new subscription, persist
    #   customer.subscription.created/.updated    — sync status/items/seats
    #   customer.subscription.deleted             — mark canceled (revoke access)
    #   invoice.paid                              — mark active (period incl. usage)
    #   invoice.payment_failed                    — mark past_due (let dunning run)
    #   customer.subscription.trial_will_end      — nudge (no state change)
    #   v1.billing.meter.error_report_triggered   — log/alert: silently-dropped usage
    class SyncSubscription < Operations::Base
      HANDLED = %w[
        checkout.session.completed
        customer.subscription.created
        customer.subscription.updated
        customer.subscription.deleted
        invoice.paid
        invoice.payment_failed
        customer.subscription.trial_will_end
        v1.billing.meter.error_report_triggered
      ].freeze

      def initialize(event, client: nil)
        @event = event
        @client = client || Vendors::Stripe::Client.new
      end

      def call
        case event_type
        when "checkout.session.completed"          then on_checkout_completed
        when "customer.subscription.created",
             "customer.subscription.updated"       then upsert_from_subscription(event_object)
        when "customer.subscription.deleted"       then on_subscription_deleted
        when "invoice.paid"                        then on_invoice_paid
        when "invoice.payment_failed"              then on_invoice_payment_failed
        when "customer.subscription.trial_will_end" then on_trial_will_end
        when "v1.billing.meter.error_report_triggered" then on_meter_error
        else
          :ignored
        end
      end

      private

      def event_type
        @event.respond_to?(:type) ? @event.type : @event["type"]
      end

      def event_object
        data = @event.respond_to?(:data) ? @event.data : @event["data"]
        data.respond_to?(:object) ? data.object : data["object"]
      end

      # checkout.session.completed carries the session; fetch the just-created
      # subscription it points at (expanding items), then upsert from that.
      def on_checkout_completed
        session = event_object
        subscription_id = read(session, :subscription)
        return :no_subscription if subscription_id.blank?

        subscription = @client.retrieve_subscription(
          subscription_id, expand: ["items.data.price"]
        )
        upsert_from_subscription(subscription)
      end

      # Upsert the local row from a Stripe subscription object.
      def upsert_from_subscription(stripe_sub)
        workspace = resolve_workspace(stripe_sub)
        return :workspace_not_found unless workspace

        record = workspace.subscription || workspace.build_subscription
        record.assign_attributes(attributes_from(stripe_sub))
        record.save!
        record
      end

      def attributes_from(stripe_sub)
        licensed = licensed_item(stripe_sub)
        {
          stripe_subscription_id: read(stripe_sub, :id),
          stripe_customer_id: read(stripe_sub, :customer),
          status: read(stripe_sub, :status),
          plan: plan_for(licensed) || :solo,
          seats: licensed ? (read(licensed, :quantity) || 1) : 1,
          current_period_end: epoch(read(stripe_sub, :current_period_end)),
          trial_ends_at: epoch(read(stripe_sub, :trial_end)),
          cancel_at: cancel_at_for(stripe_sub)
        }.compact
      end

      def on_subscription_deleted
        workspace = resolve_workspace(event_object)
        return :workspace_not_found unless workspace

        record = workspace.subscription
        return :no_subscription unless record

        record.update!(status: "canceled", cancel_at: Time.current)
        record
      end

      # invoice.paid / invoice.payment_failed reference the subscription on the
      # invoice. Recent API versions nest it under parent.subscription_details.
      def on_invoice_paid
        update_status_from_invoice("active")
      end

      def on_invoice_payment_failed
        update_status_from_invoice("past_due")
      end

      def update_status_from_invoice(status)
        record = subscription_for_invoice(event_object)
        return :no_subscription unless record

        record.update!(status: status)
        record
      end

      def on_trial_will_end
        # No state change — surface a nudge to add a payment method.
        Rails.logger.info(
          "[Stripe] trial_will_end for subscription=#{read(event_object, :id)}"
        )
        :acknowledged
      end

      # The important meter event: ingested usage with an unknown customer id,
      # missing payload key, or no matching meter is silently dropped = unbilled
      # usage. Log loudly so it can be alerted on / repaired.
      def on_meter_error
        Rails.logger.error(
          "[Stripe] v1.billing.meter.error_report_triggered: #{event_object.inspect}"
        )
        :alerted
      end

      # ── Helpers ───────────────────────────────────────────────────────────

      # Find the workspace: prefer the metadata stamped at checkout, else match by
      # the local stripe_subscription_id / stripe_customer_id.
      def resolve_workspace(stripe_sub)
        from_metadata(stripe_sub) ||
          Workspace.joins(:subscription)
                   .find_by(subscriptions: { stripe_subscription_id: read(stripe_sub, :id) }) ||
          Workspace.joins(:subscription)
                   .find_by(subscriptions: { stripe_customer_id: read(stripe_sub, :customer) })
      end

      def from_metadata(stripe_sub)
        metadata = read(stripe_sub, :metadata)
        workspace_id = metadata && (read(metadata, :workspace_id))
        workspace_id.present? ? Workspace.find_by(id: workspace_id) : nil
      end

      def subscription_for_invoice(invoice)
        subscription_id = invoice_subscription_id(invoice)
        return nil if subscription_id.blank?

        Subscription.find_by(stripe_subscription_id: subscription_id)
      end

      # Handle both pre- and post-Basil invoice shapes.
      def invoice_subscription_id(invoice)
        direct = read(invoice, :subscription)
        return direct if direct.present?

        parent = read(invoice, :parent)
        details = parent && read(parent, :subscription_details)
        details && read(details, :subscription)
      end

      # The licensed (seat/plan) item — the one whose price maps to a plan and
      # carries a quantity. Metered items have usage_type=metered.
      def licensed_item(stripe_sub)
        items_data(stripe_sub).find do |item|
          price = read(item, :price)
          plan_for_price_id(read(price, :id)).present?
        end
      end

      def items_data(stripe_sub)
        items = read(stripe_sub, :items)
        return [] unless items

        read(items, :data) || []
      end

      def plan_for(licensed_item)
        return nil unless licensed_item

        price = read(licensed_item, :price)
        plan_for_price_id(read(price, :id))
      end

      # Reverse the credential price ids back to a plan key.
      def plan_for_price_id(price_id)
        return nil if price_id.blank?

        price_to_plan[price_id]
      end

      def price_to_plan
        @price_to_plan ||= Vendors::Stripe::Client::PLAN_PRICE_KEYS.keys.each_with_object({}) do |plan, map|
          id = safe_plan_price_id(plan)
          map[id] = plan if id.present?
        end
      end

      def safe_plan_price_id(plan)
        @client.plan_price_id(plan)
      rescue Vendors::Base::NotConfiguredError
        nil
      end

      def cancel_at_for(stripe_sub)
        cancel_at = epoch(read(stripe_sub, :cancel_at))
        return cancel_at if cancel_at

        return epoch(read(stripe_sub, :current_period_end)) if read(stripe_sub, :cancel_at_period_end)

        nil
      end

      def epoch(seconds)
        seconds.present? ? Time.zone.at(seconds.to_i) : nil
      end

      # Read an attribute from either a Stripe::* object (method/[]) or a Hash with
      # string/symbol keys.
      def read(object, key)
        return nil if object.nil?

        if object.respond_to?(:[])
          object[key] || object[key.to_s]
        elsif object.respond_to?(key)
          object.public_send(key)
        end
      end
    end
  end
end
