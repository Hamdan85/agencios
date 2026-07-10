# frozen_string_literal: true

module Operations
  module Credits
    # Shared post-commit broadcast for the credit ops (Debit/Refund/Grant/
    # Purchase/Adjust). Each op returns the mutated CreditWallet on its success
    # path (and a symbol when nothing moved); calling broadcast_balance with that
    # result pushes the fresh balance to the workspace `credits_<id>` stream so the
    # credit counter in the app shell updates in real time. Never raises.
    module BroadcastsBalance
      private

      def broadcast_balance(result)
        return result unless result.is_a?(CreditWallet)

        Broadcaster.credits(result.workspace_id, 'balance_changed', available: result.available)
        result
      end
    end
  end
end
