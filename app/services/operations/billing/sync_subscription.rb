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
        when 'checkout.session.completed' then on_checkout_completed
        when 'customer.subscription.created',
             'customer.subscription.updated'       then upsert_from_subscription(event_object)
        when 'customer.subscription.deleted'       then on_subscription_deleted
        when 'invoice.paid'                        then on_invoice_paid
        when 'invoice.payment_failed'              then on_invoice_payment_failed
        when 'customer.subscription.trial_will_end' then on_trial_will_end
        when 'v1.billing.meter.error_report_triggered' then on_meter_error
        else
          :ignored
        end
      end

      private

      def event_type
        @event.respond_to?(:type) ? @event.type : @event['type']
      end

      def event_object
        data = @event.respond_to?(:data) ? @event.data : @event['data']
        data.respond_to?(:object) ? data.object : data['object']
      end

      # checkout.session.completed carries the session. A credit-pack purchase
      # (mode=payment) tops up the wallet; a subscription checkout upserts the
      # subscription and records that a card is now on file (card-required trial).
      def on_checkout_completed
        session = event_object
        return on_credit_pack_purchased(session) if credit_pack_session?(session)

        subscription_id = read(session, :subscription)
        return :no_subscription if subscription_id.blank?

        subscription = @client.retrieve_subscription(
          subscription_id, expand: ['items.data.price']
        )
        record = upsert_from_subscription(subscription)
        if record.is_a?(Subscription)
          # Checkout collected a card ⇒ trial valid; and the trial is now consumed
          # so it won't be granted again on a future checkout.
          record.update!(card_on_file: true, trial_used: true)
          # Grant the monthly credits ONLY when the checkout charged immediately
          # (no-trial purchase). During a trial the subscription is `trialing` and
          # gets NO credits — otherwise a user could spend them and cancel before
          # paying. Trial conversions are granted later, on the first paid invoice.
          grant_monthly_credits(record) unless record.trialing?
        end
        record
      end

      def credit_pack_session?(session)
        metadata = read(session, :metadata)
        metadata && read(metadata, :purpose).to_s == 'credit_pack'
      end

      # Apply a purchased credit pack to the wallet. Idempotent on the session id.
      def on_credit_pack_purchased(session)
        metadata = read(session, :metadata)
        workspace = Workspace.find_by(id: read(metadata, :workspace_id))
        return :workspace_not_found unless workspace

        result = Operations::Credits::Purchase.call(
          workspace: workspace,
          amount: read(metadata, :credits).to_i,
          reference: read(session, :id),
          description_key: 'credits.ledger.pack_purchase', description_params: { pack: read(metadata, :pack) }
        )
        # Credit-pack revenue — server-only (a Stripe checkout webhook).
        track_billing('credit_pack_purchased', workspace,
                      credits: read(metadata, :credits).to_i, pack: read(metadata, :pack),
                      amount_cents: read(session, :amount_total).to_i, currency: read(session, :currency))
        result
      end

      # Grant (reset) the plan's monthly included-credit allotment, expiring at the
      # period end. Called on checkout + each paid renewal.
      def grant_monthly_credits(subscription)
        amount = Pricing.included_credits_for(subscription.plan)
        return if amount <= 0

        Operations::Credits::Grant.call(
          workspace: subscription.workspace,
          amount: amount,
          expires_at: subscription.current_period_end || 1.month.from_now,
          description_key: 'credits.ledger.plan_monthly_named', description_params: { plan: subscription.plan }
        )
      end

      # Upsert the local row from a Stripe subscription object.
      def upsert_from_subscription(stripe_sub)
        workspace = resolve_workspace(stripe_sub)
        return :workspace_not_found unless workspace

        record = workspace.subscription || workspace.build_subscription
        record.assign_attributes(attributes_from(stripe_sub))
        record.save!
        # Catches a downgrade applied outside the app (e.g. the Stripe dashboard)
        # that leaves more active members than the new plan allows. Never removes
        # members — just flags the workspace so writes are gated (see
        # Controllers::Base#require_seat_compliance!) until the owner reconciles.
        workspace.sync_seat_compliance!
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
          interval: interval_from(licensed) || 'month',
          cancel_at: cancel_at_for(stripe_sub),
          # Only ever upgrade to true (nil is compacted out) so a later event
          # without an expanded payment method can't clear a known card.
          card_on_file: read(stripe_sub, :default_payment_method).present? || nil
        }.compact
      end

      def on_subscription_deleted
        workspace = resolve_workspace(event_object)
        return :workspace_not_found unless workspace

        record = workspace.subscription
        return :no_subscription unless record

        record.update!(status: 'canceled', cancel_at: Time.current)
        notify_owner(workspace, record, :canceled)
        # Churn — reliably captured server-side even when the cancel happens in
        # the Stripe portal (the browser never fires it).
        track_billing('subscription_canceled', workspace, plan: record.plan)
        record
      end

      # invoice.paid / invoice.payment_failed reference the subscription on the
      # invoice. Recent API versions nest it under parent.subscription_details.
      def on_invoice_paid
        record = update_status_from_invoice('active')
        # A paid invoice = a valid card + a fresh billing period ⇒ refill credits,
        # but ONLY when money actually changed hands (amount_paid > 0). A R$0 trial
        # invoice must not grant credits (that would reopen the trial exploit).
        if record.is_a?(Subscription)
          record.update!(card_on_file: true, trial_used: true)
          if invoice_charged?
            grant_monthly_credits(record)
            # SaaS revenue — a server-only event (the browser never sees the
            # invoice). No client counterpart, so no double-count.
            track_billing('subscription_payment', record.workspace,
                          plan: record.plan, amount_cents: read(event_object, :amount_paid).to_i,
                          currency: read(event_object, :currency))
          end
        end
        record
      end

      # Whether the paid invoice actually collected money (not a R$0 trial invoice).
      def invoice_charged?
        read(event_object, :amount_paid).to_i.positive?
      end

      def on_invoice_payment_failed
        record = update_status_from_invoice('past_due')
        notify_owner(record.workspace, record, :payment_failed) if record.is_a?(Subscription)
        record
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
        workspace = resolve_workspace(event_object)
        notify_owner(workspace, workspace&.subscription, :trial_ending)
        :acknowledged
      end

      # Email the workspace owner about a billing lifecycle change. Best-effort —
      # a mail failure must never break webhook reconciliation.
      def notify_owner(workspace, subscription, kind)
        return if workspace.nil? || workspace.owner&.email.blank?

        SubscriptionMailer.public_send(kind, workspace: workspace, subscription: subscription).deliver_later
      rescue StandardError => e
        Rails.logger.warn("[Stripe] subscription #{kind} email failed: #{e.message}")
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

      # Emit a server-side PostHog revenue/lifecycle event for a workspace,
      # keyed on its owner (matching the SPA identify) and grouped by workspace.
      # These are all server-only events with no browser counterpart, so PostHog
      # never double-counts them.
      def track_billing(event, workspace, **properties)
        owner = workspace&.owner
        return unless owner

        Vendors::Posthog::Actions::Capture.call(
          user: owner, event: event, properties: properties, groups: { workspace: workspace.id }
        )
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
        workspace_id = metadata && read(metadata, :workspace_id)
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
          detect_plan(read(item, :price)).present?
        end
      end

      def items_data(stripe_sub)
        items = read(stripe_sub, :items)
        return [] unless items

        read(items, :data) || []
      end

      def plan_for(licensed_item)
        return nil unless licensed_item

        detect_plan(read(licensed_item, :price))
      end

      # The billing cycle ("month"/"year") from the licensed item's price.
      def interval_from(licensed_item)
        return nil unless licensed_item

        price = read(licensed_item, :price)
        recurring = price && read(price, :recurring)
        recurring && read(recurring, :interval)
      end

      # Map a Stripe price object back to a plan key. Order matters for
      # grandfathering: the PRODUCT is stable across price changes, then the exact
      # price id, then the lookup_key, then the legacy credential map.
      def detect_plan(price)
        return nil unless price

        product = read(price, :product)
        product = read(product, :id) if product.respond_to?(:id) # expanded object
        by_product = PricingPlan.find_by(stripe_product_id: product) if product.present?
        return by_product.key if by_product

        price_id = read(price, :id)
        if price_id.present?
          by_price = PricingPlan.where('stripe_price_id = :id OR stripe_annual_price_id = :id', id: price_id).first
          return by_price.key if by_price
        end

        lookup = read(price, :lookup_key)
        if lookup.present?
          by_lookup = PricingPlan.where('stripe_lookup_key = :lk OR stripe_annual_lookup_key = :lk', lk: lookup).first
          return by_lookup.key if by_lookup
        end

        price_to_plan[price_id] # legacy credential fallback
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
