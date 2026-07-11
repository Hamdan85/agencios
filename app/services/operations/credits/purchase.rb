# frozen_string_literal: true

module Operations
  module Credits
    # Add prepaid credits from a top-up pack purchase (Stripe one-time payment).
    # Purchased credits stack and roll over. Idempotent on `reference` (the Stripe
    # payment/session id) so a re-delivered webhook can't double-credit.
    class Purchase < Operations::Base
      include BroadcastsBalance

      def initialize(workspace:, amount:, reference:, user: nil, description: nil, expires_at: nil,
                     description_key: nil, description_params: {})
        @workspace          = workspace
        @amount             = amount.to_i
        @reference          = reference.to_s
        @user               = user
        @description        = description
        @description_key    = description_key
        @description_params = description_params
        @expires_at         = expires_at || Pricing::CREDIT_PACK_TTL.from_now
      end

      def call
        return :noop if @amount <= 0

        wallet = Operations::Credits::EnsureWallet.call(workspace: @workspace)

        result = ApplicationRecord.transaction do
          wallet.lock!
          return :duplicate if already_applied?

          wallet.update!(purchased_balance: wallet.purchased_balance + @amount)

          @workspace.credit_transactions.create!(
            user: @user,
            kind: 'purchase', bucket: 'purchased',
            amount: @amount, granted_delta: 0, purchased_delta: @amount,
            balance_after: wallet.granted_balance + wallet.purchased_balance,
            expires_at: @expires_at,
            description: @description,
            description_key: (@description ? nil : (@description_key || 'credits.ledger.purchase')),
            description_params: @description_params,
            metadata: { reference: @reference }
          )
          wallet
        end

        broadcast_balance(result)
      end

      private

      def already_applied?
        return false if @reference.blank?

        @workspace.credit_transactions
                  .where(kind: 'purchase')
                  .where("metadata->>'reference' = ?", @reference)
                  .exists?
      end
    end
  end
end
