# frozen_string_literal: true

module Controllers
  module Registrations
    # Registers a user + their first workspace, returning the User. The cookie
    # session lifecycle is an HTTP concern handled by the controller.
    class Create < Base
      def initialize(params:)
        @params = params
      end

      def call
        user, workspace = Operations::Users::Register.call(
          email: @params.require(:email),
          password: @params.require(:password),
          name: @params[:name],
          workspace_name: @params[:workspace_name]
        )

        # PostHog owns `sign_up` server-side (reliable, unblockable). The SPA
        # sends the same conversion to GTM + the Meta Pixel only, so PostHog
        # counts it exactly once. distinct_id = user.id matches the SPA identify.
        Vendors::Posthog::Actions::Capture.call(
          user: user, event: 'sign_up',
          properties: { method: 'password', plan: workspace&.plan },
          groups: workspace ? { workspace: workspace.id } : nil
        )
        user
      end
    end
  end
end
