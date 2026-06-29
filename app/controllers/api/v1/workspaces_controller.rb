# frozen_string_literal: true

module Api
  module V1
    class WorkspacesController < BaseController
      def show   = render_ok(Controllers::Workspaces::Show.call)
      def update = render_ok(Controllers::Workspaces::Update.call(params:))

      # POST /api/v1/workspace/switch
      def switch = render_ok(Controllers::Workspaces::Switch.call(params:))
    end
  end
end
