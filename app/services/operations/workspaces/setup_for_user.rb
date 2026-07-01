# frozen_string_literal: true

module Operations
  module Workspaces
    # Bootstraps a brand-new workspace for a user: makes them the owner, creates
    # the singleton Setting, an empty credit wallet, and a Subscription in the
    # `incomplete` state (NO access — there is no free tier). The real trial only
    # starts once the owner completes Stripe Checkout (card-required), which the
    # webhook flips to `trialing` with a card on file.
    class SetupForUser < Operations::Base
      def initialize(user:, name: nil)
        @user = user
        @name = name
      end

      def call
        workspace = Workspace.create!(
          name: workspace_name,
          slug: unique_slug(workspace_name),
          default_handle: default_handle
        )

        Membership.create!(workspace: workspace, user: @user, role: :owner)
        Setting.create!(workspace: workspace)
        Subscription.create!(
          workspace: workspace,
          plan: :solo,
          status: 'incomplete', # awaiting payment — no access until checkout
          seats: 1,
          card_on_file: false
        )
        Operations::Credits::EnsureWallet.call(workspace: workspace)

        workspace
      end

      private

      def workspace_name
        @name.presence || "Agência de #{@user.display_name}"
      end

      def default_handle
        "@#{@user.display_name.parameterize.delete('-')}"
      end

      def unique_slug(name)
        base = name.parameterize.presence || 'agencia'
        base = base[0, 56]
        candidate = base
        suffix = 1
        while Workspace.exists?(slug: candidate)
          suffix += 1
          candidate = "#{base}-#{suffix}"
        end
        candidate
      end
    end
  end
end
