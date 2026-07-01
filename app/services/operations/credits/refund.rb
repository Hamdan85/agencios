# frozen_string_literal: true

module Operations
  module Credits
    # Return the credits spent on a generation (e.g. the async render failed).
    # Refunds to the exact buckets the debit came from, using the split recorded
    # on the original debit transaction. Idempotent: a generation already
    # refunded is a no-op.
    class Refund < Operations::Base
      def initialize(generation:, description: nil)
        @generation  = generation
        @description = description
      end

      def call
        workspace = @generation.workspace
        return :none if workspace.godfathered?

        ApplicationRecord.transaction do
          debit = workspace.credit_transactions
                           .where(generation_id: @generation.id, kind: 'debit')
                           .order(:created_at).last
          return :none unless debit
          return :already if refunded?(workspace)

          wallet = Operations::Credits::EnsureWallet.call(workspace: workspace)
          wallet.lock!

          granted   = -debit.granted_delta
          purchased = -debit.purchased_delta

          wallet.update!(
            granted_balance: wallet.granted_balance + granted,
            purchased_balance: wallet.purchased_balance + purchased
          )

          workspace.credit_transactions.create!(
            generation: @generation, user: @generation.user,
            kind: 'refund', bucket: debit.bucket,
            amount: granted + purchased, granted_delta: granted, purchased_delta: purchased,
            balance_after: wallet.granted_balance + wallet.purchased_balance,
            description: @description || 'Estorno — geração falhou'
          )
          wallet
        end
      end

      private

      def refunded?(workspace)
        workspace.credit_transactions.exists?(generation_id: @generation.id, kind: 'refund')
      end
    end
  end
end
