# frozen_string_literal: true

module Operations
  module Credits
    # Top a godfathered workspace's monthly credit allotment back up to its
    # configured `monthly_credit_limit`. Godfathered workspaces don't pay Stripe,
    # so the invoice.paid grant path never fires for them — this stands in for it,
    # refilling the granted bucket once per calendar month.
    #
    # Idempotent within a cycle: it only (re)grants when there's no live grant for
    # the current window (or when `force:` is passed — e.g. an admin just changed
    # the limit). No-op unless the workspace is godfathered WITH a limit set
    # (unlimited godfathered workspaces never touch the wallet).
    #
    # Called lazily from the debit/preflight paths and swept monthly by
    # GrantGodfatheredCreditsJob.
    class EnsureGodfatheredGrant < Operations::Base
      def initialize(workspace:, force: false)
        @workspace = workspace
        @force     = force
      end

      def call
        return :noop unless @workspace.credit_limited?

        wallet = Operations::Credits::EnsureWallet.call(workspace: @workspace)
        return wallet if !@force && wallet.granted_current?

        Operations::Credits::Grant.call(
          workspace: @workspace,
          amount: @workspace.monthly_credit_limit,
          expires_at: Time.current.end_of_month,
          description: 'Créditos mensais (cortesia godfathered)'
        )
      end
    end
  end
end
