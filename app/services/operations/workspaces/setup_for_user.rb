# frozen_string_literal: true

module Operations
  module Workspaces
    # Bootstraps a brand-new workspace for a user: makes them the owner, creates
    # the singleton Setting + a trialing Subscription. This is the canonical
    # workspace creator (the aggregate root + its owned singletons).
    class SetupForUser < Operations::Base
      TRIAL_LENGTH = 14.days

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
          workspace:     workspace,
          plan:          :solo,
          status:        "trialing",
          seats:         1,
          trial_ends_at: TRIAL_LENGTH.from_now
        )

        workspace
      end

      private

      def workspace_name
        @name.presence || "Agência de #{@user.display_name}"
      end

      def default_handle
        "@#{@user.display_name.parameterize.delete("-")}"
      end

      def unique_slug(name)
        base = name.parameterize.presence || "agencia"
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
