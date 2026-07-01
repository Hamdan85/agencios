# frozen_string_literal: true

module Controllers
  module Credits
    # GET /api/v1/credits — the workspace's credit wallet + recent ledger + the
    # catalog of packs it can buy.
    class Show < Base
      def call
        wallet = Operations::Credits::EnsureWallet.call(workspace: workspace)

        {
          wallet: {
            available:         workspace.godfathered? ? nil : wallet.available,
            granted:           wallet.live_granted,
            purchased:         wallet.purchased_balance,
            granted_expires_at: wallet.granted_expires_at&.iso8601,
            unlimited:         workspace.godfathered?
          },
          packs: Pricing.credit_packs.map { |p| p.slice(:key, :name, :price_cents, :credits) },
          costs: Pricing.public_catalog[:credit_costs],
          transactions: serialize_transactions(wallet)
        }
      end

      private

      def serialize_transactions(_wallet)
        workspace.credit_transactions.recent_first.limit(30).map do |tx|
          {
            id: tx.id, kind: tx.kind, amount: tx.amount,
            balance_after: tx.balance_after, description: tx.description,
            created_at: tx.created_at.iso8601
          }
        end
      end
    end
  end
end
