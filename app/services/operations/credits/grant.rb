# frozen_string_literal: true

module Operations
  module Credits
    # Grant the plan's monthly credit allotment. Replaces (does not stack) the
    # granted bucket — any unused granted credits from the previous cycle expire.
    # Called on subscription renewal (invoice.paid) and on plan start.
    class Grant < Operations::Base
      def initialize(workspace:, amount:, expires_at:, description: nil)
        @workspace   = workspace
        @amount      = amount.to_i
        @expires_at  = expires_at
        @description = description
      end

      def call
        wallet = Operations::Credits::EnsureWallet.call(workspace: @workspace)

        ApplicationRecord.transaction do
          wallet.lock!
          expire_previous!(wallet)

          wallet.update!(granted_balance: @amount, granted_expires_at: @expires_at)

          @workspace.credit_transactions.create!(
            kind: 'grant', bucket: 'granted',
            amount: @amount, granted_delta: @amount, purchased_delta: 0,
            balance_after: wallet.granted_balance + wallet.purchased_balance,
            expires_at: @expires_at,
            description: @description || 'Créditos mensais do plano'
          )
          wallet
        end
      end

      private

      # Zero out any leftover granted credits from the prior cycle before the new
      # grant lands (use-it-or-lose-it).
      def expire_previous!(wallet)
        leftover = wallet.granted_balance
        return if leftover.zero?

        wallet.update!(granted_balance: 0)
        @workspace.credit_transactions.create!(
          kind: 'expire', bucket: 'granted',
          amount: -leftover, granted_delta: -leftover, purchased_delta: 0,
          balance_after: wallet.purchased_balance,
          description: 'Créditos mensais não usados expirados'
        )
      end
    end
  end
end
