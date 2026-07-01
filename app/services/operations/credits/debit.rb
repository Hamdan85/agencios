# frozen_string_literal: true

module Operations
  module Credits
    # Spend credits for a generation. Granted (monthly) credits are consumed
    # first, then purchased. Raises Operations::Errors::InsufficientCredits if the
    # wallet can't cover the amount. Godfathered workspaces never debit.
    #
    # Takes a row lock so concurrent generations can't oversell the balance.
    # Records a `debit` CreditTransaction carrying the per-bucket split so a later
    # refund can return credits to the exact buckets.
    class Debit < Operations::Base
      def initialize(workspace:, amount:, generation: nil, user: nil, description: nil)
        @workspace   = workspace
        @amount      = amount.to_i
        @generation  = generation
        @user        = user || Current.user
        @description = description
      end

      def call
        return :free if @amount <= 0
        return :godfathered if @workspace.godfathered?

        wallet = Operations::Credits::EnsureWallet.call(workspace: @workspace)

        ApplicationRecord.transaction do
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
          description: 'Créditos mensais expirados'
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
          description: @description || default_description
        )
      end

      def default_description
        kind = @generation&.kind
        kind ? "Geração de #{kind}" : 'Débito de créditos'
      end
    end
  end
end
