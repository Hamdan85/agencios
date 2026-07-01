# frozen_string_literal: true

module Operations
  module Credits
    # Apply a signed credit correction (reconciling an estimate to the real cost).
    # Positive `amount` returns credits (to the purchased bucket); negative charges
    # more, best-effort clamped to the available balance so it NEVER raises — the
    # generation already happened, we just true-up the ledger. No-op for
    # godfathered workspaces and for a zero delta.
    class Adjust < Operations::Base
      def initialize(workspace:, amount:, generation: nil, description: nil)
        @workspace   = workspace
        @amount      = amount.to_i
        @generation  = generation
        @description = description
      end

      def call
        return :noop if @amount.zero? || @workspace.godfathered?

        wallet = Operations::Credits::EnsureWallet.call(workspace: @workspace)

        ApplicationRecord.transaction do
          wallet.lock!

          if @amount.positive?
            wallet.update!(purchased_balance: wallet.purchased_balance + @amount)
            record(wallet, granted: 0, purchased: @amount)
          else
            take = [-@amount, wallet.granted_balance + wallet.purchased_balance].min
            from_granted   = [take, wallet.granted_balance].min
            from_purchased = take - from_granted
            wallet.update!(
              granted_balance:   wallet.granted_balance - from_granted,
              purchased_balance: wallet.purchased_balance - from_purchased
            )
            record(wallet, granted: -from_granted, purchased: -from_purchased)
          end
          wallet
        end
      end

      private

      def record(wallet, granted:, purchased:)
        bucket = if granted != 0 && purchased != 0 then "mixed"
                 elsif granted != 0 then "granted"
                 else "purchased"
                 end
        @workspace.credit_transactions.create!(
          generation: @generation, user: @generation&.user,
          kind: "adjustment", bucket: bucket,
          amount: granted + purchased, granted_delta: granted, purchased_delta: purchased,
          balance_after: wallet.granted_balance + wallet.purchased_balance,
          description: @description || "Ajuste de créditos"
        )
      end
    end
  end
end
