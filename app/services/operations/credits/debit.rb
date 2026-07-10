# frozen_string_literal: true

module Operations
  module Credits
    # Spend credits for a generation. Granted (monthly) credits are consumed
    # first, then purchased. Raises Operations::Errors::InsufficientCredits if the
    # wallet can't cover the amount. Unlimited godfathered workspaces never debit
    # (capped godfathered workspaces spend from their monthly allotment).
    #
    # Takes a row lock so concurrent generations can't oversell the balance.
    # Records a `debit` CreditTransaction carrying the per-bucket split so a later
    # refund can return credits to the exact buckets.
    class Debit < Operations::Base
      include BroadcastsBalance

      def initialize(workspace:, amount:, generation: nil, user: nil, description: nil)
        @workspace   = workspace
        @amount      = amount.to_i
        @generation  = generation
        @user        = user || Current.user
        @description = description
      end

      def call
        return :free if @amount <= 0
        # Unlimited godfathered workspaces never deduct from a balance (they have
        # none) — but they DO consume real vendor cost, so we still record a
        # notional debit (no bucket movement) for the usage chart + cost analysis.
        # Capped godfathered ones (a monthly_credit_limit is set) spend from the
        # refilled monthly allotment exactly like a paying workspace.
        if @workspace.godfathered? && !@workspace.credit_limited?
          record_notional_debit
          return :godfathered
        end

        Operations::Credits::EnsureGodfatheredGrant.call(workspace: @workspace) if @workspace.credit_limited?

        wallet = Operations::Credits::EnsureWallet.call(workspace: @workspace)

        result = ApplicationRecord.transaction do
          wallet.lock!
          expire_stale_grant!(wallet)

          available = wallet.granted_balance + wallet.purchased_balance
          if available < @amount
            raise Operations::Errors::InsufficientCredits.new(required: @amount, available: available)
          end

          from_granted   = [@amount, wallet.granted_balance].min
          from_purchased = @amount - from_granted

          wallet.update!(
            granted_balance: wallet.granted_balance - from_granted,
            purchased_balance: wallet.purchased_balance - from_purchased
          )

          record_transaction(wallet, from_granted, from_purchased)
          wallet
        end

        broadcast_balance(result)
      end

      private

      def expire_stale_grant!(wallet)
        return unless wallet.granted_expired?

        expired = wallet.granted_balance
        wallet.update!(granted_balance: 0)
        @workspace.credit_transactions.create!(
          kind: 'expire', bucket: 'granted',
          amount: -expired, granted_delta: -expired, purchased_delta: 0,
          balance_after: wallet.purchased_balance,
          description_key: 'credits.ledger.expired'
        )
      end

      def record_transaction(wallet, from_granted, from_purchased)
        bucket = if from_granted.positive? && from_purchased.positive? then 'mixed'
                 elsif from_granted.positive? then 'granted'
                 else 'purchased'
                 end

        @workspace.credit_transactions.create!(
          generation: @generation, user: @user,
          kind: 'debit', bucket: bucket,
          amount: -@amount, granted_delta: -from_granted, purchased_delta: -from_purchased,
          balance_after: wallet.granted_balance + wallet.purchased_balance,
          description: @description, description_key: (@description ? nil : default_description_key)
        )
      end

      # A godfathered "spend" with no wallet behind it: the ledger records what the
      # generation WOULD have cost (for the usage chart + cost math), but no bucket
      # moves and there's no balance to draw down (granted/purchased deltas are 0).
      def record_notional_debit
        @workspace.credit_transactions.create!(
          generation: @generation, user: @user,
          kind: 'debit', bucket: 'granted',
          amount: -@amount, granted_delta: 0, purchased_delta: 0,
          balance_after: 0,
          description: @description, description_key: (@description ? nil : default_description_key)
        )
      rescue StandardError => e
        Rails.logger.warn("[Credits::Debit] notional godfathered debit failed: #{e.message}")
      end

      def default_description_key
        kind = @generation&.kind
        kind ? "credits.ledger.debit_#{kind}" : 'credits.ledger.debit_generic'
      end
    end
  end
end
