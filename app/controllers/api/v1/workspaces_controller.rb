# frozen_string_literal: true

module Api
  module V1
    class WorkspacesController < BaseController
      # Readable/switchable behind the paywall so the user can jump to a paid
      # workspace or spin up a new one.
      skip_billing_gate

      def show   = render_ok(Controllers::Workspaces::Show.call)
      def create = render_created(Controllers::Workspaces::Create.call(params:))
      def update = render_ok(Controllers::Workspaces::Update.call(params:))

      # POST /api/v1/workspace/switch
      def switch = render_ok(Controllers::Workspaces::Switch.call(params:))
    end
  end
end
