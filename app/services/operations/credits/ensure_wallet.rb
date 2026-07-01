# frozen_string_literal: true

module Operations
  module Credits
    # Returns the workspace's credit wallet, creating it on first touch.
    class EnsureWallet < Operations::Base
      def initialize(workspace:)
        @workspace = workspace
      end

      def call
        @workspace.credit_wallet || @workspace.create_credit_wallet!
      rescue ActiveRecord::RecordNotUnique
        @workspace.credit_wallet(true)
      end
    end
  end
end
