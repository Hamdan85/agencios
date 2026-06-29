# frozen_string_literal: true

module Api
  module V1
    # The current user's authorized external apps (MCP connectors like Claude).
    class ConnectionsController < BaseController
      def index   = render_ok(Controllers::Connections::Index.call)
      def destroy = render_ok(Controllers::Connections::Destroy.call(params:))
    end
  end
end
