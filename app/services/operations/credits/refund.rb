# frozen_string_literal: true

module Operations
  module Credits
    # Return the credits spent on a generation (e.g. the async render failed).
    # Refunds to the exact buckets the debit came from, using the split recorded
    # on the original debit transaction. Idempotent per ATTEMPT: the newest
    # debit is refunded once — but a NEW debit after a refund (a charged retry
    # that failed again) refunds again, so a fail→retry→fail loop never eats
    # credits for renders that were never delivered.
    class Refund < Operations::Base
      include BroadcastsBalance

      def initialize(generation:, description: nil)
        @generation  = generation
        @description = description
      end

      def call
        workspace = @generation.workspace
        # Capped godfathered workspaces really debited, so they really refund;
        # only unlimited godfathered workspaces have nothing to return.
        return :none if workspace.godfathered? && !workspace.credit_limited?

        result = ApplicationRecord.transaction do
          debit = workspace.credit_transactions
                           .where(generation_id: @generation.id, kind: 'debit')
                           .order(:created_at).last
          return :none unless debit
          return :already if refunded?(workspace, debit)

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
            description: @description, description_key: (@description ? nil : 'credits.ledger.refund_failed_generation')
          )
          wallet
        end

        broadcast_balance(result)
      end

      private

      # This debit is settled only if a refund NEWER than it exists — an older
      # refund belongs to a previous failed attempt, not to this charge.
      def refunded?(workspace, debit)
        workspace.credit_transactions
                 .where(generation_id: @generation.id, kind: 'refund')
                 .where(created_at: debit.created_at..)
                 .exists?
      end
    end
  end
end
