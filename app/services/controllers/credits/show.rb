# frozen_string_literal: true

module Controllers
  module Credits
    # GET /api/v1/credits — the workspace's credit wallet + recent ledger + the
    # catalog of packs it can buy.
    class Show < Base
      def call
        # Refill first so the balance reflects the current cycle's allotment.
        Operations::Credits::EnsureGodfatheredGrant.call(workspace: workspace) if workspace.credit_limited?
        wallet = Operations::Credits::EnsureWallet.call(workspace: workspace).reload

        unlimited = workspace.godfathered? && !workspace.credit_limited?

        {
          wallet: {
            available: unlimited ? nil : wallet.available,
            granted: wallet.live_granted,
            purchased: wallet.purchased_balance,
            granted_expires_at: wallet.granted_expires_at&.iso8601,
            unlimited: unlimited,
            monthly_limit: workspace.credit_limited? ? workspace.monthly_credit_limit : nil
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
            balance_after: tx.balance_after, description: tx.display_description,
            created_at: tx.created_at.iso8601
          }
        end
      end
    end
  end
end
