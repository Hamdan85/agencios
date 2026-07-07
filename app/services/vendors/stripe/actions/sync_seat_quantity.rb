# frozen_string_literal: true

module Vendors
  module Stripe
    module Actions
      # Push a seat quantity to the subscription's licensed item (Stripe prorates
      # licensed-quantity changes automatically). Returns true when Stripe was
      # updated, false when the quantity already matched or no licensed item was
      # found.
      class SyncSeatQuantity
        def self.call(...) = new(...).call

        def initialize(subscription:, quantity:, client: nil)
          @subscription = subscription # local Subscription record
          @quantity     = quantity.to_i
          @client       = client || Client.new
        end

        def call
          stripe_sub = @client.retrieve_subscription(
            @subscription.stripe_subscription_id, expand: ['items.data.price']
          )
          item = LicensedItem.find(stripe_sub)
          return false unless item
          return false if item.quantity == @quantity

          @client.update_subscription_item(
            item['id'] || item.id,
            quantity: @quantity, proration_behavior: 'create_prorations'
          )
          true
        end
      end
    end
  end
end
