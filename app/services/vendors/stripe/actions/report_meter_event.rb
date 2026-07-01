# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Emit one Billing Meter event for a billable generation.
      #
      # POST /v1/billing/meter_events. The `event_name` is the meter's name per
      # kind (`carousel_generation` / `video_generation`). The `identifier` is the
      # idempotency/dedup key, derived deterministically from the immutable
      # generation id (`"#{kind}:#{id}"`) so a retried job is never double-billed
      # (Stripe enforces identifier uniqueness for ~24h+). The payload carries the
      # workspace's `stripe_customer_id` and a `value` of 1 per generation.
      #
      # See docs/integrations/stripe-billing.md §4.
      class ReportMeterEvent
        def self.call(...) = new(...).call

        # Maps Generation kind → the meter's `event_name`. Only carousel/video are
        # metered; image generation is tracked but never sent here.
        EVENT_NAMES = {
          'carousel' => 'carousel_generation',
          'video' => 'video_generation'
        }.freeze

        def initialize(generation, client: nil)
          @generation = generation
          @client = client || Client.new
        end

        # Returns the Stripe::Billing::MeterEvent.
        def call
          @client.create_meter_event(
            event_name: event_name,
            stripe_customer_id: stripe_customer_id,
            value: 1,
            identifier: identifier,
            timestamp: @generation.created_at.to_i
          )
        end

        private

        def event_name
          EVENT_NAMES.fetch(@generation.kind.to_s) do
            raise Vendors::Base::Error,
                  "Generation kind não medível: #{@generation.kind.inspect}"
          end
        end

        # Deterministic, immutable dedup key — never a timestamp.
        def identifier
          "#{@generation.kind}:#{@generation.id}"
        end

        def stripe_customer_id
          id = @generation.workspace.subscription&.stripe_customer_id
          return id if id.present?

          raise Vendors::Base::Error,
                "Workspace #{@generation.workspace_id} sem stripe_customer_id; não é possível medir uso."
        end
      end
    end
  end
end
